// WASAPI render-endpoint loopback. No microphone, injection, game API or memory.
// API contract: Microsoft Learn, "Loopback Recording" and IAudioCaptureClient.
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Diagnostics;

namespace PlayerEvidence {
    [ComImport,Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class Enumerator {}
    [ComImport,Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IDevices {
        [PreserveSig]int EnumAudioEndpoints(int flow,int mask,out IntPtr devices);
        [PreserveSig]int GetDefaultAudioEndpoint(int flow,int role,out IDevice device);
    }
    [ComImport,Guid("D666063F-1587-4E43-81F1-B948E807363F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IDevice {
        [PreserveSig]int Activate(ref Guid iid,int clsctx,IntPtr activation,out IClient client);
    }
    [ComImport,Guid("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IClient {
        [PreserveSig]int Initialize(int share,int flags,long duration,long period,IntPtr format,IntPtr session);
        [PreserveSig]int GetBufferSize(out uint size);
        [PreserveSig]int GetStreamLatency(out long latency);
        [PreserveSig]int GetCurrentPadding(out uint frames);
        [PreserveSig]int IsFormatSupported(int mode,IntPtr format,out IntPtr closest);
        [PreserveSig]int GetMixFormat(out IntPtr format);
        [PreserveSig]int GetDevicePeriod(out long normal,out long minimum);
        [PreserveSig]int Start();
        [PreserveSig]int Stop();
        [PreserveSig]int Reset();
        [PreserveSig]int SetEventHandle(IntPtr handle);
        [PreserveSig]int GetService(ref Guid iid,out ICapture capture);
    }
    [ComImport,Guid("C8ADBD64-E71E-48A0-A4DE-185C395CD317"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface ICapture {
        [PreserveSig]int GetBuffer(out IntPtr data,out uint frames,out uint flags,out ulong position,out ulong qpc);
        [PreserveSig]int ReleaseBuffer(uint frames);
        [PreserveSig]int GetNextPacketSize(out uint frames);
    }
    public static class Loopback {
        static Thread worker; static volatile bool stopping;
        public static string Error="";
        public static long Frames; public static int SampleRate,Channels,Bits;
        public static long StartedQpc; public static long QpcFrequency=Stopwatch.Frequency;
        public static string PacketTimingPath="";
        public static long PacketCount,TimestampErrors,Discontinuities;
        static void Check(int hr){Marshal.ThrowExceptionForHR(hr);}
        public static void Start(string path) {
            if(worker!=null)throw new InvalidOperationException("Audio capture already active");
            stopping=false;Error="";Frames=0;PacketCount=TimestampErrors=Discontinuities=0;
            PacketTimingPath=path+".packets.jsonl";
            worker=new Thread(()=>Capture(path));worker.IsBackground=true;worker.SetApartmentState(ApartmentState.MTA);worker.Start();
        }
        public static void Stop(){stopping=true;if(worker!=null&&!worker.Join(5000))throw new TimeoutException("Audio capture cleanup");worker=null;}
        static void Capture(string path) {
            IDevices devices=null;IDevice device=null;IClient client=null;ICapture capture=null;IntPtr format=IntPtr.Zero;
            try {
                devices=(IDevices)new Enumerator();Check(devices.GetDefaultAudioEndpoint(0,1,out device));
                Guid clientId=typeof(IClient).GUID;Check(device.Activate(ref clientId,23,IntPtr.Zero,out client));
                Check(client.GetMixFormat(out format));int bytes=18+(ushort)Marshal.ReadInt16(format,16);byte[] fmt=new byte[bytes];Marshal.Copy(format,fmt,0,bytes);
                Channels=(ushort)Marshal.ReadInt16(format,2);SampleRate=Marshal.ReadInt32(format,4);Bits=(ushort)Marshal.ReadInt16(format,14);int align=(ushort)Marshal.ReadInt16(format,12);
                Check(client.Initialize(0,0x20000,1000000,0,format,IntPtr.Zero));Guid captureId=typeof(ICapture).GUID;Check(client.GetService(ref captureId,out capture));
                using(var packets=new StreamWriter(new FileStream(PacketTimingPath,FileMode.CreateNew,FileAccess.Write,FileShare.Read)))
                using(var stream=new FileStream(path,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.Read))using(var w=new BinaryWriter(stream)) {
                    w.Write(System.Text.Encoding.ASCII.GetBytes("RIFF"));w.Write(0);w.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt "));w.Write(bytes);w.Write(fmt);w.Write(System.Text.Encoding.ASCII.GetBytes("data"));long lengthOffset=stream.Position;w.Write(0);long dataStart=stream.Position;
                    StartedQpc=Stopwatch.GetTimestamp();Check(client.Start());
                    while(!stopping) {
                        uint count;Check(capture.GetNextPacketSize(out count));
                        while(count>0) {
                            IntPtr buffer;uint frames,flags;ulong position,qpc;Check(capture.GetBuffer(out buffer,out frames,out flags,out position,out qpc));
                            if(frames==0)break;
                            try {
                                // WASAPI supplies the first frame's device position
                                // and QPC time in 100 ns units. Preserve each packet;
                                // concatenated samples alone cannot locate gaps.
                                packets.WriteLine("{\"file_frame\":"+Frames+",\"frames\":"+frames+",\"flags\":"+flags+",\"device_position\":"+position+",\"qpc_100ns\":"+qpc+"}");
                                PacketCount++;if((flags&4)!=0)TimestampErrors++;if((flags&1)!=0)Discontinuities++;
                                byte[] block=new byte[checked((int)frames*align)];if((flags&2)==0)Marshal.Copy(buffer,block,0,block.Length);w.Write(block);Frames+=frames;
                            }
                            finally{Check(capture.ReleaseBuffer(frames));}
                            Check(capture.GetNextPacketSize(out count));
                        }
                        Thread.Sleep(5);
                    }
                    Check(client.Stop());long size=stream.Position;stream.Position=lengthOffset;w.Write(checked((int)(size-dataStart)));stream.Position=4;w.Write(checked((int)(size-8)));
                }
            } catch(Exception e){Error=e.GetType().Name+":"+e.Message;}
            finally {if(format!=IntPtr.Zero)Marshal.FreeCoTaskMem(format);foreach(object value in new object[]{capture,client,device,devices})if(value!=null)Marshal.ReleaseComObject(value);}
        }
    }
}
