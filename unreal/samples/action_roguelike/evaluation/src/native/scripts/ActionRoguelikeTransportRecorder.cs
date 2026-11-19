using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Threading;

// Host-owned, read-only capture. Start before launching the game, so blocking
// input/capture operations cannot discard the publisher's incremental batches.
public sealed class ARTransportRecorder : IDisposable
{
    public sealed class Record
    {
        public string Kind, Path, Sha256;
        public long ByteLength;
        public DateTime PublishedUtc;
    }
    readonly string snapshot, events, root;
    readonly List<Record> records = new List<Record>();
    readonly Dictionary<string, string> hashes = new Dictionary<string, string>();
    readonly Dictionary<string, int> denied = new Dictionary<string, int>();
    readonly Thread worker;
    volatile bool stopped;
    public string Fault { get; private set; }
    public string SnapshotPath { get { return snapshot; } }
    public string EventsPath { get { return events; } }
    public ARTransportRecorder(string snapshotPath, string eventsPath)
    {
        snapshot = Path.GetFullPath(snapshotPath);
        events = Path.GetFullPath(eventsPath);
        root = events + ".captured";
        if (Directory.Exists(root)) throw new IOException("Recorder output must be fresh.");
        Directory.CreateDirectory(root);
        worker = new Thread(Run) { IsBackground = true, Name = "AR read-only transport recorder", Priority = ThreadPriority.AboveNormal };
        worker.Start();
    }
    public Record[] ReadRecords() { lock (records) return records.ToArray(); }
    void Capture(string path, string kind)
    {
        byte[] bytes;
        DateTime written;
        try
        {
            if (!File.Exists(path)) return;
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("state_transport_reparse_point");
            using (var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                // Bind the timestamp to the same open file as the bytes. A
                // path lookup between atomic replacements can return the
                // missing-file 1601 sentinel before Open sees the new file.
                written = File.GetLastWriteTimeUtc(input.SafeFileHandle);
                if (input.Length < 2 || input.Length > 4194304) throw new InvalidOperationException("state_document_size_invalid");
                bytes = new byte[(int)input.Length];
                input.ReadExactly(bytes);
            }
        }
        catch (FileNotFoundException) { return; }
        catch (DirectoryNotFoundException) { return; }
        catch (UnauthorizedAccessException)
        {
            // Windows may report delete-pending atomic replacement as access
            // denied. Retry only reading the publisher file, with a finite cap.
            denied.TryGetValue(kind, out var count);
            denied[kind] = count + 1;
            if (count >= 200) throw;
            return;
        }
        catch (IOException ex)
        {
            // An atomic replacement can briefly remove the target. Retry only
            // source-sharing races; inability to retain evidence is a host fault.
            if ((ex.HResult & 0xffff) != 32 && (ex.HResult & 0xffff) != 33) throw;
            return;
        }
        denied[kind] = 0;
        string hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        if (hashes.TryGetValue(kind, out var old) && old == hash) return;
        string output = Path.Combine(root, records.Count.ToString("D10") + "-" + kind + ".json");
        // Retention errors are never treated as source publication races.
        File.WriteAllBytes(output + ".tmp", bytes);
        File.Move(output + ".tmp", output);
        File.SetLastWriteTimeUtc(output, written);
        var record = new Record { Kind = kind, Path = output, Sha256 = hash,
            ByteLength = bytes.Length, PublishedUtc = written };
        lock (records) records.Add(record);
        hashes[kind] = hash;
    }
    void Run()
    {
        try
        {
            while (!stopped) { Capture(snapshot, "snapshot"); Capture(events, "events"); Thread.Sleep(5); }
            Capture(snapshot, "snapshot"); Capture(events, "events");
        }
        catch (Exception ex) { Fault = ex.Message; }
    }
    public void Dispose() { stopped = true; if (!worker.Join(5000)) throw new IOException("Recorder cleanup timeout."); }
}
