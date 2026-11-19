using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using UnityEngine;

namespace OmniGame.Benchmark.SignCircuit.Evaluator
{
    [Serializable]
    public sealed class SignCircuitCheckpointEvidence
    {
        public string check_id;
        public string status;
        public string generated_utc;
        public int frame;
        public string scene;
        public string[] observations;
    }

    [Serializable]
    public sealed class SignCircuitEvidenceRecord
    {
        public string test_id;
        public string generated_utc;
        public string evaluation_session_id;
        public int process_id;
        public string scene;
        public int frame;
        public string[] observations;
        public double expected_value;
        public double actual_value;
        public string actual_text;
        public string persistence_kind;
        public string persistence_id;
        public string persistence_fingerprint_sha256;
        public string persistence_modified_utc;
        public bool backing_checked_before_scene_load;
        public bool checkpoint_partial_credit;
        public bool test_complete;
        public SignCircuitCheckpointEvidence[] checkpoints;
    }

    [Serializable]
    public sealed class SignCircuitFreshSeed
    {
        public string generated_utc;
        public string evaluation_session_id;
        public string best_time_text;
        public string best_time_number;
        public string source_scene;
        public int source_process_id;
        public string company_name;
        public string product_name;
        public string persistent_data_path;
        public string baseline_capture_utc;
        public string saved_capture_utc;
        public SignCircuitPersistenceRecord persisted_record;
    }

    [Serializable]
    public sealed class SignCircuitPersistenceRecord
    {
        public string kind;
        public string id;
        public string value_kind;
        public string fingerprint_sha256;
        public string modified_utc;
        public long byte_length;
        public double[] numeric_values;
    }

    [Serializable]
    public sealed class SignCircuitPersistenceSnapshot
    {
        public string captured_utc;
        public string company_name;
        public string product_name;
        public string persistent_data_path;
        public string player_prefs_registry_path;
        public string registry_last_write_utc;
        public SignCircuitPersistenceRecord[] records;
    }

    public static class SignCircuitEvidenceWriter
    {
        const string OutputArgument = "-signCircuitEvidenceOutput";
        const string SessionArgument = "-signCircuitEvaluationSession";
        const string CheckpointPending = "pending";
        const string CheckpointActive = "active";
        const string CheckpointPassed = "passed";
        static readonly Dictionary<string, SignCircuitEvidenceRecord>
            ActiveCheckpointRecords =
                new Dictionary<string, SignCircuitEvidenceRecord>(StringComparer.Ordinal);

        public static string OutputDirectory => ReadArgument(OutputArgument);
        public static string EvaluationSessionId => ReadArgument(SessionArgument);

        /// <summary>
        /// Writes a replaceable, non-scoring trace beside the formal evidence tree.
        /// It exists only so a failed Unity trajectory can be diagnosed before the
        /// invocation-owned run root is deleted. Successful tests remove their trace.
        /// </summary>
        public static void WriteDiagnosticTrace(
            string traceId,
            IEnumerable<string> observations)
        {
            string evidenceDirectory = OutputDirectory;
            if (string.IsNullOrWhiteSpace(evidenceDirectory)) return;
            string rawRoot = Path.GetDirectoryName(evidenceDirectory);
            if (string.IsNullOrWhiteSpace(rawRoot)) return;
            string directory = Path.Combine(rawRoot, "diagnostics");
            Directory.CreateDirectory(directory);
            string path = Path.Combine(directory, SafeName(traceId) + ".log");
            var lines = new List<string>
            {
                "diagnostic_only=true",
                "evaluation_session_id=" + EvaluationSessionId,
                "process_id=" + System.Diagnostics.Process.GetCurrentProcess().Id,
                "scene=" + UnityEngine.SceneManagement.SceneManager.GetActiveScene().path,
                "frame=" + Time.frameCount
            };
            if (observations != null) lines.AddRange(observations);
            File.WriteAllLines(path, lines);
        }

        public static void DeleteDiagnosticTrace(string traceId)
        {
            string evidenceDirectory = OutputDirectory;
            if (string.IsNullOrWhiteSpace(evidenceDirectory)) return;
            string rawRoot = Path.GetDirectoryName(evidenceDirectory);
            if (string.IsNullOrWhiteSpace(rawRoot)) return;
            string path = Path.Combine(rawRoot, "diagnostics",
                SafeName(traceId) + ".log");
            if (File.Exists(path)) File.Delete(path);
            string directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(directory) && Directory.Exists(directory) &&
                Directory.GetFileSystemEntries(directory).Length == 0)
            {
                Directory.Delete(directory);
            }
        }

        public static void Write(string testId, IEnumerable<string> observations)
        {
            string directory = OutputDirectory;
            if (string.IsNullOrWhiteSpace(directory)) return;

            Directory.CreateDirectory(directory);
            WriteUnique(testId, NewRecord(testId, observations));
        }

        /// <summary>
        /// Starts a replaceable formal evidence ledger for a composite NUnit
        /// journey. Each entry corresponds to one already-declared scoring
        /// checkpoint. A later assertion may fail the NUnit testcase, but the
        /// scorer can still retain entries that were independently marked passed.
        /// </summary>
        public static void BeginCheckpoints(
            string testId,
            IEnumerable<string> checkpointIds)
        {
            string directory = OutputDirectory;
            if (string.IsNullOrWhiteSpace(directory)) return;
            if (string.IsNullOrWhiteSpace(testId))
                throw new ArgumentException("Evidence test id is required.", nameof(testId));

            string[] ids = (checkpointIds ?? Array.Empty<string>())
                .Where(id => !string.IsNullOrWhiteSpace(id))
                .ToArray();
            if (ids.Length == 0 || ids.Distinct(StringComparer.Ordinal).Count() != ids.Length)
                throw new ArgumentException(
                    "Checkpoint ids must be non-empty and unique.", nameof(checkpointIds));

            Directory.CreateDirectory(directory);
            string path = EvidencePath(testId);
            if (File.Exists(path) || ActiveCheckpointRecords.ContainsKey(testId))
                throw new IOException(
                    $"Duplicate formal checkpoint evidence for test '{testId}' is not allowed: {path}");

            SignCircuitEvidenceRecord record = NewRecord(testId, Array.Empty<string>());
            record.checkpoint_partial_credit = true;
            record.test_complete = false;
            record.checkpoints = ids.Select(id => new SignCircuitCheckpointEvidence
            {
                check_id = id,
                status = CheckpointPending,
                generated_utc = string.Empty,
                frame = 0,
                scene = string.Empty,
                observations = Array.Empty<string>()
            }).ToArray();
            ActiveCheckpointRecords.Add(testId, record);
            WriteCheckpointSnapshot(record);
        }

        public static void EnterCheckpoint(
            string testId,
            string checkpointId,
            IEnumerable<string> observations = null)
        {
            SignCircuitEvidenceRecord record = RequireCheckpointRecord(testId);
            SignCircuitCheckpointEvidence checkpoint =
                RequireCheckpoint(record, checkpointId);
            SignCircuitCheckpointEvidence otherActive = record.checkpoints
                .FirstOrDefault(item => item.status == CheckpointActive &&
                                        !string.Equals(item.check_id, checkpointId,
                                            StringComparison.Ordinal));
            if (otherActive != null)
                throw new InvalidOperationException(
                    $"Checkpoint '{otherActive.check_id}' is still active before '{checkpointId}'.");
            if (checkpoint.status == CheckpointPassed)
                throw new InvalidOperationException(
                    $"Checkpoint '{checkpointId}' was already passed.");

            checkpoint.status = CheckpointActive;
            StampCheckpoint(checkpoint, observations);
            StampRecord(record);
            WriteCheckpointSnapshot(record);
        }

        public static void PassCheckpoint(
            string testId,
            string checkpointId,
            IEnumerable<string> observations = null)
        {
            SignCircuitEvidenceRecord record = RequireCheckpointRecord(testId);
            SignCircuitCheckpointEvidence checkpoint =
                RequireCheckpoint(record, checkpointId);
            if (checkpoint.status != CheckpointActive)
                throw new InvalidOperationException(
                    $"Checkpoint '{checkpointId}' must be active before it can pass.");

            checkpoint.status = CheckpointPassed;
            StampCheckpoint(checkpoint, observations);
            StampRecord(record);
            WriteCheckpointSnapshot(record);
        }

        public static void CompleteCheckpoints(
            string testId,
            IEnumerable<string> observations)
        {
            SignCircuitEvidenceRecord record = RequireCheckpointRecord(testId);
            string[] incomplete = record.checkpoints
                .Where(item => item.status != CheckpointPassed)
                .Select(item => item.check_id)
                .ToArray();
            if (incomplete.Length != 0)
                throw new InvalidOperationException(
                    "Composite evidence cannot complete before every declared checkpoint passes: " +
                    string.Join(", ", incomplete));

            record.test_complete = true;
            record.observations = observations?.ToArray() ?? Array.Empty<string>();
            StampRecord(record);
            WriteCheckpointSnapshot(record);
            ActiveCheckpointRecords.Remove(testId);
        }

        public static void WriteFreshResult(
            string testId,
            double expected,
            double actual,
            string actualText,
            SignCircuitPersistenceRecord survivingRecord,
            bool backingCheckedBeforeSceneLoad,
            IEnumerable<string> observations)
        {
            string directory = OutputDirectory;
            if (string.IsNullOrWhiteSpace(directory)) return;

            Directory.CreateDirectory(directory);
            SignCircuitEvidenceRecord record = NewRecord(testId, observations);
            record.expected_value = expected;
            record.actual_value = actual;
            record.actual_text = actualText ?? string.Empty;
            record.persistence_kind = survivingRecord?.kind ?? string.Empty;
            record.persistence_id = survivingRecord?.id ?? string.Empty;
            record.persistence_fingerprint_sha256 =
                survivingRecord?.fingerprint_sha256 ?? string.Empty;
            record.persistence_modified_utc =
                survivingRecord?.modified_utc ?? string.Empty;
            record.backing_checked_before_scene_load = backingCheckedBeforeSceneLoad;
            WriteUnique(testId, record);
        }

        public static void WriteFreshSeed(
            string bestTimeText,
            SignCircuitPersistenceSnapshot baseline,
            SignCircuitPersistenceSnapshot saved,
            SignCircuitPersistenceRecord persistedRecord)
        {
            string directory = OutputDirectory;
            if (string.IsNullOrWhiteSpace(directory)) return;

            Directory.CreateDirectory(directory);
            Match numeric = Regex.Match(bestTimeText ?? string.Empty, @"\d+(?:[\.,]\d+)?");
            var seed = new SignCircuitFreshSeed
            {
                generated_utc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                evaluation_session_id = EvaluationSessionId,
                best_time_text = bestTimeText ?? string.Empty,
                best_time_number = numeric.Success ? numeric.Value.Replace(',', '.') : string.Empty,
                source_scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene().path,
                source_process_id = System.Diagnostics.Process.GetCurrentProcess().Id,
                company_name = Application.companyName,
                product_name = Application.productName,
                persistent_data_path = Application.persistentDataPath,
                baseline_capture_utc = baseline?.captured_utc ?? string.Empty,
                saved_capture_utc = saved?.captured_utc ?? string.Empty,
                persisted_record = persistedRecord
            };
            File.WriteAllText(Path.Combine(directory, "fresh-seed.json"),
                JsonUtility.ToJson(seed, true));
        }

        static string ReadArgument(string key)
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int index = 0; index < args.Length - 1; index++)
            {
                if (string.Equals(args[index], key, StringComparison.OrdinalIgnoreCase))
                {
                    return args[index + 1].Trim('"');
                }
            }
            return string.Empty;
        }

        static SignCircuitEvidenceRecord NewRecord(
            string testId,
            IEnumerable<string> observations)
        {
            return new SignCircuitEvidenceRecord
            {
                test_id = testId,
                generated_utc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                evaluation_session_id = EvaluationSessionId,
                process_id = System.Diagnostics.Process.GetCurrentProcess().Id,
                scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene().path,
                frame = Time.frameCount,
                observations = observations?.ToArray() ?? Array.Empty<string>()
            };
        }

        static SignCircuitEvidenceRecord RequireCheckpointRecord(string testId)
        {
            if (!ActiveCheckpointRecords.TryGetValue(testId ?? string.Empty,
                    out SignCircuitEvidenceRecord record))
                throw new InvalidOperationException(
                    $"No active checkpoint evidence exists for test '{testId}'.");
            return record;
        }

        static SignCircuitCheckpointEvidence RequireCheckpoint(
            SignCircuitEvidenceRecord record,
            string checkpointId)
        {
            SignCircuitCheckpointEvidence[] matches = (record.checkpoints ??
                    Array.Empty<SignCircuitCheckpointEvidence>())
                .Where(item => string.Equals(item.check_id, checkpointId,
                    StringComparison.Ordinal))
                .ToArray();
            if (matches.Length != 1)
                throw new InvalidOperationException(
                    $"Expected one checkpoint '{checkpointId}', found {matches.Length}.");
            return matches[0];
        }

        static void StampCheckpoint(
            SignCircuitCheckpointEvidence checkpoint,
            IEnumerable<string> observations)
        {
            checkpoint.generated_utc =
                DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
            checkpoint.frame = Time.frameCount;
            checkpoint.scene = UnityEngine.SceneManagement.SceneManager
                .GetActiveScene().path;
            checkpoint.observations = observations?.ToArray() ?? Array.Empty<string>();
            if (checkpoint.frame <= 0)
                throw new InvalidOperationException(
                    "Checkpoint evidence cannot be written before the Unity player loop advances.");
        }

        static void StampRecord(SignCircuitEvidenceRecord record)
        {
            record.generated_utc =
                DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
            record.process_id = System.Diagnostics.Process.GetCurrentProcess().Id;
            record.scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene().path;
            record.frame = Time.frameCount;
            if (record.frame <= 0)
                throw new InvalidOperationException(
                    "Formal evidence cannot be written before the Unity player loop advances.");
        }

        static void WriteCheckpointSnapshot(SignCircuitEvidenceRecord record)
        {
            if (string.IsNullOrWhiteSpace(record.evaluation_session_id))
                throw new InvalidOperationException(
                    "The evaluator session id is required before evidence can be written.");
            File.WriteAllText(EvidencePath(record.test_id),
                JsonUtility.ToJson(record, true));
        }

        static string EvidencePath(string testId) =>
            Path.Combine(OutputDirectory, SafeName(testId) + ".json");

        static void WriteUnique(string testId, SignCircuitEvidenceRecord record)
        {
            if (string.IsNullOrWhiteSpace(testId))
                throw new ArgumentException("Evidence test id is required.", nameof(testId));
            if (string.IsNullOrWhiteSpace(record.evaluation_session_id))
                throw new InvalidOperationException(
                    "The evaluator session id is required before evidence can be written.");
            if (record.frame <= 0)
                throw new InvalidOperationException(
                    "Formal evidence cannot be written before the Unity player loop advances.");

            string path = EvidencePath(testId);
            if (File.Exists(path))
                throw new IOException(
                    $"Duplicate formal evidence for test '{testId}' is not allowed: {path}");
            File.WriteAllText(path, JsonUtility.ToJson(record, true));
        }

        static string SafeName(string value) => Regex.Replace(
            value ?? "evidence", @"[^A-Za-z0-9._-]", "_");
    }

    public static class SignCircuitPersistenceProbe
    {
        const int MaximumInspectableFileBytes = 1024 * 1024;
        static readonly Regex NumberPattern = new Regex(
            @"[-+]?\d+(?:[\.,]\d+)?", RegexOptions.CultureInvariant);

        public static SignCircuitPersistenceSnapshot Capture()
        {
            var records = new List<SignCircuitPersistenceRecord>();
            string registryPath = PlayerPrefsRegistryPath();
            string registryWrite = string.Empty;
#if UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN
            CaptureRegistry(registryPath, records, out registryWrite);
#endif
            CaptureFiles(Application.persistentDataPath, records);
            return new SignCircuitPersistenceSnapshot
            {
                captured_utc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                company_name = Application.companyName,
                product_name = Application.productName,
                persistent_data_path = Application.persistentDataPath,
                player_prefs_registry_path = registryPath,
                registry_last_write_utc = registryWrite,
                records = records.OrderBy(item => item.id, StringComparer.Ordinal).ToArray()
            };
        }

        public static SignCircuitPersistenceRecord FindChangedRecord(
            SignCircuitPersistenceSnapshot before,
            SignCircuitPersistenceSnapshot after)
        {
            var beforeById = (before?.records ?? Array.Empty<SignCircuitPersistenceRecord>())
                .ToDictionary(item => item.id, item => item, StringComparer.Ordinal);
            foreach (SignCircuitPersistenceRecord record in
                     after?.records ?? Array.Empty<SignCircuitPersistenceRecord>())
            {
                if (!beforeById.TryGetValue(record.id, out SignCircuitPersistenceRecord prior) ||
                    !string.Equals(prior.fingerprint_sha256, record.fingerprint_sha256,
                        StringComparison.Ordinal))
                {
                    return record;
                }
            }
            return null;
        }

        public static SignCircuitPersistenceRecord FindMatchingRecord(
            SignCircuitPersistenceSnapshot snapshot,
            SignCircuitPersistenceRecord expectedRecord)
        {
            if (snapshot == null || expectedRecord == null) return null;
            return (snapshot.records ?? Array.Empty<SignCircuitPersistenceRecord>())
                .FirstOrDefault(record =>
                    string.Equals(record.id, expectedRecord.id, StringComparison.Ordinal) &&
                    string.Equals(record.kind, expectedRecord.kind, StringComparison.Ordinal) &&
                    string.Equals(record.fingerprint_sha256,
                        expectedRecord.fingerprint_sha256, StringComparison.Ordinal));
        }

        public static SignCircuitPersistenceRecord FindUnchangedRecord(
            SignCircuitPersistenceSnapshot snapshot,
            IEnumerable<SignCircuitPersistenceRecord> candidates)
        {
            if (snapshot == null || candidates == null) return null;
            var current = (snapshot.records ?? Array.Empty<SignCircuitPersistenceRecord>())
                .ToDictionary(item => item.id, item => item, StringComparer.Ordinal);
            foreach (SignCircuitPersistenceRecord candidate in candidates
                         .Where(item => item != null)
                         .OrderBy(item => item.id, StringComparer.Ordinal))
            {
                if (current.TryGetValue(candidate.id, out SignCircuitPersistenceRecord record) &&
                    string.Equals(record.kind, candidate.kind, StringComparison.Ordinal) &&
                    string.Equals(record.fingerprint_sha256,
                        candidate.fingerprint_sha256, StringComparison.Ordinal))
                {
                    return record;
                }
            }
            return null;
        }

        public static SignCircuitPersistenceRecord FindRecordByIdentity(
            SignCircuitPersistenceSnapshot snapshot,
            SignCircuitPersistenceRecord expectedRecord)
        {
            if (snapshot == null || expectedRecord == null) return null;
            return (snapshot.records ?? Array.Empty<SignCircuitPersistenceRecord>())
                .FirstOrDefault(record =>
                    string.Equals(record.id, expectedRecord.id, StringComparison.Ordinal) &&
                    string.Equals(record.kind, expectedRecord.kind,
                        StringComparison.Ordinal));
        }

        public static SignCircuitPersistenceRecord[] ChangedRecords(
            SignCircuitPersistenceSnapshot before,
            SignCircuitPersistenceSnapshot after)
        {
            var beforeById = (before?.records ?? Array.Empty<SignCircuitPersistenceRecord>())
                .ToDictionary(item => item.id, item => item, StringComparer.Ordinal);
            return (after?.records ?? Array.Empty<SignCircuitPersistenceRecord>())
                .Where(record => !beforeById.TryGetValue(record.id,
                                      out SignCircuitPersistenceRecord prior) ||
                                 !string.Equals(prior.fingerprint_sha256,
                                     record.fingerprint_sha256,
                                     StringComparison.Ordinal))
                .OrderBy(item => item.id, StringComparer.Ordinal)
                .ToArray();
        }

        public static bool TryParseNumber(string value, out double number)
        {
            Match match = NumberPattern.Match(value ?? string.Empty);
            return double.TryParse(
                match.Success ? match.Value.Replace(',', '.') : string.Empty,
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out number);
        }

        static string PlayerPrefsRegistryPath()
        {
            string company = SanitizeRegistryComponent(Application.companyName);
            string product = SanitizeRegistryComponent(Application.productName);
#if UNITY_EDITOR
            return $@"Software\Unity\UnityEditor\{company}\{product}";
#else
            return $@"Software\{company}\{product}";
#endif
        }

        static string SanitizeRegistryComponent(string value)
        {
            return (value ?? string.Empty).Replace("\\", "_").Replace("/", "_");
        }

#if UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN
        static void CaptureRegistry(
            string subKeyPath,
            ICollection<SignCircuitPersistenceRecord> records,
            out string lastWriteUtc)
        {
            lastWriteUtc = string.Empty;
            if (RegOpenKeyEx(HkeyCurrentUser, subKeyPath, 0, KeyRead,
                    out IntPtr key) != 0)
            {
                return;
            }
            try
            {
                uint classLength = 0;
                int infoResult = RegQueryInfoKey(
                    key, null, ref classLength, IntPtr.Zero,
                    out _, out _, out _, out uint valueCount,
                    out uint maxValueNameLength, out uint maxValueLength,
                    out _, out long fileTime);
                if (infoResult != 0) return;
                lastWriteUtc = DateTime.FromFileTimeUtc(fileTime)
                    .ToString("O", CultureInfo.InvariantCulture);

                for (uint index = 0; index < valueCount; index++)
                {
                    var nameBuilder = new StringBuilder((int)maxValueNameLength + 2);
                    uint nameLength = (uint)nameBuilder.Capacity;
                    byte[] data = new byte[Math.Max(1, (int)maxValueLength + 8)];
                    uint dataLength = (uint)data.Length;
                    int enumResult = RegEnumValue(
                        key, index, nameBuilder, ref nameLength, IntPtr.Zero,
                        out uint valueType, data, ref dataLength);
                    if (enumResult != 0) continue;
                    string name = nameBuilder.ToString();
                    if (IsEvaluatorOrUnityOwnedRegistryValue(name)) continue;
                    byte[] bytes = data.Take((int)dataLength).ToArray();
                    records.Add(new SignCircuitPersistenceRecord
                    {
                        kind = "player_prefs_registry",
                        id = "player_prefs:" + name,
                        value_kind = RegistryTypeName(valueType),
                        fingerprint_sha256 = Hash(bytes),
                        modified_utc = lastWriteUtc,
                        byte_length = bytes.LongLength,
                        numeric_values = ExtractRegistryNumbers(valueType, bytes)
                    });
                }
            }
            finally
            {
                RegCloseKey(key);
            }
        }

        static bool IsEvaluatorOrUnityOwnedRegistryValue(string name)
        {
            string normalized = name ?? string.Empty;
            return normalized.StartsWith("Unity", StringComparison.OrdinalIgnoreCase) ||
                   normalized.StartsWith("unity.", StringComparison.OrdinalIgnoreCase) ||
                   normalized.StartsWith("unity_", StringComparison.OrdinalIgnoreCase) ||
                   normalized.StartsWith("PT_", StringComparison.OrdinalIgnoreCase) ||
                   normalized.StartsWith("Screenmanager", StringComparison.OrdinalIgnoreCase);
        }

        static string RegistryTypeName(uint valueType)
        {
            switch (valueType)
            {
                case 1: return "REG_SZ";
                case 2: return "REG_EXPAND_SZ";
                case 3: return "REG_BINARY";
                case 4: return "REG_DWORD";
                case 7: return "REG_MULTI_SZ";
                case 11: return "REG_QWORD";
                default: return "REG_" + valueType.ToString(CultureInfo.InvariantCulture);
            }
        }

        static double[] ExtractRegistryNumbers(uint valueType, byte[] bytes)
        {
            var numbers = new List<double>();
            if (valueType == 4 && bytes.Length >= 4)
            {
                int integer = BitConverter.ToInt32(bytes, 0);
                numbers.Add(integer);
                AddFinite(numbers, BitConverter.ToSingle(bytes, 0));
                if (bytes.Length >= 8)
                    AddFinite(numbers, BitConverter.ToDouble(bytes, 0));
            }
            else if (valueType == 11 && bytes.Length >= 8)
            {
                long longInteger = BitConverter.ToInt64(bytes, 0);
                AddFinite(numbers, BitConverter.Int64BitsToDouble(longInteger));
                if (Math.Abs((double)longInteger) < 1000000000d) numbers.Add(longInteger);
            }
            if (valueType == 1 || valueType == 2 || valueType == 7)
            {
                AddTextNumbers(numbers, Encoding.Unicode.GetString(bytes).TrimEnd('\0'));
            }
            else if (valueType == 3)
            {
                AddTextNumbers(numbers, DecodeLikelyText(bytes));
                if (bytes.Length == 4)
                    AddFinite(numbers, BitConverter.ToSingle(bytes, 0));
                if (bytes.Length == 8)
                    AddFinite(numbers, BitConverter.ToDouble(bytes, 0));
            }
            return numbers.Distinct().ToArray();
        }

        const uint KeyRead = 0x20019;
        static readonly IntPtr HkeyCurrentUser = new IntPtr(unchecked((int)0x80000001));

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
        static extern int RegOpenKeyEx(
            IntPtr hKey, string subKey, uint options, uint samDesired, out IntPtr result);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
        static extern int RegQueryInfoKey(
            IntPtr hKey, StringBuilder keyClass, ref uint classLength, IntPtr reserved,
            out uint subKeyCount, out uint maxSubKeyLength, out uint maxClassLength,
            out uint valueCount, out uint maxValueNameLength, out uint maxValueLength,
            out uint securityDescriptorLength, out long lastWriteTime);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
        static extern int RegEnumValue(
            IntPtr hKey, uint index, StringBuilder valueName, ref uint valueNameLength,
            IntPtr reserved, out uint valueType, byte[] data, ref uint dataLength);

        [DllImport("advapi32.dll")]
        static extern int RegCloseKey(IntPtr hKey);

#endif

        static void CaptureFiles(
            string root,
            ICollection<SignCircuitPersistenceRecord> records)
        {
            if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root)) return;
            string fullRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) +
                              Path.DirectorySeparatorChar;
            foreach (string path in Directory.GetFiles(root, "*", SearchOption.AllDirectories))
            {
                try
                {
                    var file = new FileInfo(path);
                    byte[] bytes = File.ReadAllBytes(path);
                    string relative = Path.GetFullPath(path).Substring(fullRoot.Length)
                        .Replace('\\', '/');
                    var numbers = new List<double>();
                    if (bytes.Length <= MaximumInspectableFileBytes)
                    {
                        AddTextNumbers(numbers, DecodeLikelyText(bytes));
                        if (bytes.Length == 4)
                            AddFinite(numbers, BitConverter.ToSingle(bytes, 0));
                        if (bytes.Length == 8)
                            AddFinite(numbers, BitConverter.ToDouble(bytes, 0));
                    }
                    records.Add(new SignCircuitPersistenceRecord
                    {
                        kind = "persistent_data_file",
                        id = "file:" + relative,
                        value_kind = "file",
                        fingerprint_sha256 = Hash(bytes),
                        modified_utc = file.LastWriteTimeUtc.ToString(
                            "O", CultureInfo.InvariantCulture),
                        byte_length = file.Length,
                        numeric_values = numbers.Distinct().ToArray()
                    });
                }
                catch
                {
                    // A locked unrelated file cannot create positive persistence evidence.
                }
            }
        }

        static void AddTextNumbers(ICollection<double> numbers, string text)
        {
            if (string.IsNullOrWhiteSpace(text)) return;
            foreach (Match match in NumberPattern.Matches(text))
            {
                if (double.TryParse(match.Value.Replace(',', '.'), NumberStyles.Float,
                        CultureInfo.InvariantCulture, out double parsed))
                {
                    AddFinite(numbers, parsed);
                }
            }
        }

        static void AddFinite(ICollection<double> numbers, double value)
        {
            if (!double.IsNaN(value) && !double.IsInfinity(value)) numbers.Add(value);
        }

        static string DecodeLikelyText(byte[] bytes)
        {
            if (bytes == null || bytes.Length == 0) return string.Empty;
            string text = Encoding.UTF8.GetString(bytes).TrimEnd('\0');
            int printable = text.Count(character =>
                !char.IsControl(character) || char.IsWhiteSpace(character));
            return printable >= Math.Max(1, text.Length * 3 / 4) ? text : string.Empty;
        }

        static string Hash(byte[] bytes)
        {
            using (SHA256 sha = SHA256.Create())
            {
                return BitConverter.ToString(sha.ComputeHash(bytes ?? Array.Empty<byte>()))
                    .Replace("-", string.Empty).ToLowerInvariant();
            }
        }
    }
}
