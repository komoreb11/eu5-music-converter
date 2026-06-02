param([string]$OggPath = "", [string]$WemPath = "")

# Cache compiled assembly to avoid recompiling every run
$cacheDir = "$env:TEMP\eu4wem_cache"
$cacheDll  = "$cacheDir\OggToWem.dll"
if (-not (Test-Path $cacheDll)) {
    New-Item -ItemType Directory -Force $cacheDir | Out-Null
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;

public class OggToWem {

    struct OggResult {
        public List<byte[]> Packets;
        public long TotalSamples;
    }

    // Single-pass OGG parser: extracts packets + total samples
    static OggResult ParseOgg(byte[] d) {
        var r = new OggResult { Packets = new List<byte[]>() };
        int pos = 0;
        byte[] buf = null; int bufLen = 0;

        while (pos <= d.Length - 27) {
            if (d[pos]!=0x4F||d[pos+1]!=0x67||d[pos+2]!=0x67||d[pos+3]!=0x53) break;
            long g = BitConverter.ToInt64(d, pos + 6);
            if (g > 0) r.TotalSamples = g;
            int nseg = d[pos + 26];
            int dp = pos + 27 + nseg;
            for (int i = 0; i < nseg; i++) {
                int sz = d[pos + 27 + i];
                if (bufLen + sz > (buf == null ? 0 : buf.Length)) {
                    var nb = new byte[Math.Max(bufLen + sz, bufLen * 2 + 256)];
                    if (buf != null) Buffer.BlockCopy(buf, 0, nb, 0, bufLen);
                    buf = nb;
                }
                Buffer.BlockCopy(d, dp, buf, bufLen, sz);
                bufLen += sz; dp += sz;
                if (sz < 255) {
                    var pkt = new byte[bufLen];
                    Buffer.BlockCopy(buf, 0, pkt, 0, bufLen);
                    r.Packets.Add(pkt);
                    bufLen = 0;
                }
            }
            pos = dp;
        }
        if (bufLen > 0) { var p = new byte[bufLen]; Buffer.BlockCopy(buf,0,p,0,bufLen); r.Packets.Add(p); }
        return r;
    }

    static void W16(BinaryWriter w, int v)  { w.Write((ushort)v); }
    static void W32(BinaryWriter w, long v) { w.Write((uint)v); }

    public static void Convert(string oggPath, string wemPath) {
        var d = File.ReadAllBytes(oggPath);
        var ogg = ParseOgg(d);
        d = null; // free memory

        if (ogg.Packets.Count < 4)
            throw new Exception("Not enough OGG packets: " + ogg.Packets.Count);

        byte[] id_pkt    = ogg.Packets[0];
        byte[] cmt_pkt   = ogg.Packets[1];
        byte[] setup_pkt = ogg.Packets[2];

        int channels    = id_pkt[11];
        int sample_rate = BitConverter.ToInt32(id_pkt, 12);
        int bs_byte     = id_pkt[28];
        int bs0_exp     = bs_byte & 0x0F;
        int bs1_exp     = (bs_byte >> 4) & 0x0F;

        // Build data chunk in memory
        using (var ms = new MemoryStream(ogg.Packets.Count * 512)) {
            var bw = new BinaryWriter(ms);
            W16(bw, id_pkt.Length);    bw.Write(id_pkt);
            W16(bw, cmt_pkt.Length);   bw.Write(cmt_pkt);
            W16(bw, setup_pkt.Length); bw.Write(setup_pkt);

            long audio_off = ms.Position;
            int max_pkt = 0;
            for (int i = 3; i < ogg.Packets.Count; i++) {
                var p = ogg.Packets[i];
                W16(bw, p.Length);
                bw.Write(p);
                if (p.Length > max_pkt) max_pkt = p.Length;
            }
            long data_end = ms.Position;
            byte[] data = ms.ToArray();

            // Build fmt extra (48 bytes)
            using (var fe = new MemoryStream(48)) {
                var fw = new BinaryWriter(fe);
                fw.Write(new byte[]{0x00,0x00,0x02,0x31,0x00,0x00}); // version
                W32(fw, ogg.TotalSamples);     // dwTotalPCMFrames
                W32(fw, audio_off);            // dwLoopStartPacketOffset
                W32(fw, data_end);             // dwLoopEndPacketOffset
                W16(fw, 0); W16(fw, 0);        // loop extras
                W32(fw, 0);                    // dwSeekTableSize
                W32(fw, audio_off);            // dwVorbisDataOffset
                W16(fw, max_pkt);              // uMaxPacketSize
                W16(fw, 0);                    // uLastGranuleExtra
                W32(fw, (1 << bs1_exp) * channels * 2); // dwDecodeAllocSize
                W32(fw, (1 << bs1_exp) * channels * 4); // dwDecodeX64AllocSize
                W32(fw, 0);                    // reserved
                fw.Write((byte)bs0_exp);
                fw.Write((byte)bs1_exp);
                byte[] extra = fe.ToArray();

                // Write WEM file
                using (var wem = new FileStream(wemPath, FileMode.Create, FileAccess.Write, FileShare.None, 65536)) {
                    var ww = new BinaryWriter(wem);
                    // RIFF header
                    ww.Write(new byte[]{0x52,0x49,0x46,0x46}); // RIFF
                    long riffSize = 4 + 8 + 18 + 2 + 48 + 8 + 16 + 8 + data.Length;
                    W32(ww, riffSize);
                    ww.Write(new byte[]{0x57,0x41,0x56,0x45}); // WAVE
                    // fmt chunk (18 + 2 + 48 = 68 bytes)
                    ww.Write(new byte[]{0x66,0x6D,0x74,0x20}); // fmt
                    W32(ww, 66);
                    W16(ww, 0xFFFF);
                    W16(ww, channels);
                    W32(ww, sample_rate);
                    W32(ww, sample_rate * channels * 2);
                    W16(ww, 0); W16(ww, 0);
                    W16(ww, 48);
                    ww.Write(extra);
                    // hash chunk
                    ww.Write(new byte[]{0x68,0x61,0x73,0x68}); // hash
                    W32(ww, 16);
                    ww.Write(new byte[16]);
                    // data chunk
                    ww.Write(new byte[]{0x64,0x61,0x74,0x61}); // data
                    W32(ww, data.Length);
                    ww.Write(data);
                }
            }
        }
    }
}
'@ -OutputAssembly $cacheDll
}
Add-Type -Path $cacheDll

# --- FNV-1 hash ---
function Get-FNV1([string]$s) {
    [uint64]$h = 2166136261; [uint64]$m = 16777619; [uint64]$mask = 4294967295
    foreach ($c in $s.ToLower().ToCharArray()) { $h=($h*$m)-band $mask; $h=$h-bxor[uint64][byte][char]$c }
    return [uint32]$h
}

# --- Find EU4 ---
if (-not $OggPath) {
    foreach ($dr in @("E:","D:","C:")) {
        foreach ($l in @("SteamLibrary","Program Files (x86)\Steam")) {
            $p = "$dr\$l\steamapps\common\Europa Universalis IV\music\maintheme.ogg"
            if (Test-Path $p) { $OggPath = $p; break }
        }
        if ($OggPath) { break }
    }
    if (-not $OggPath) { Write-Host "EU4 not found"; exit 1 }
}

# --- Find mod Media dir ---
if (-not $WemPath) {
    $MediaDir = $null
    foreach ($dr in @("E:","D:","C:")) {
        foreach ($l in @("SteamLibrary","Program Files (x86)\Steam")) {
            $base = "$dr\$l\steamapps\workshop\content\3450310"
            if (-not (Test-Path $base)) { continue }
            foreach ($dir in (Get-ChildItem $base -Directory -EA SilentlyContinue)) {
                if ((Test-Path "$($dir.FullName)\.metadata\metadata.json") -and
                    ((Get-Content "$($dir.FullName)\.metadata\metadata.json" -Raw) -like '*"eu4_soundtrack"*')) {
                    $MediaDir = "$($dir.FullName)\loading_screen\sound\banks\windows\Media"
                    break
                }
            }
            if ($MediaDir) { break }
        }
        if ($MediaDir) { break }
    }
    if (-not $MediaDir) { Write-Host "Mod not found"; exit 1 }
    New-Item -ItemType Directory -Force $MediaDir | Out-Null
    $WemPath = "$MediaDir\$(Get-FNV1 'MusicPlayer_eu4_maintheme').wem"
}

# --- Convert ---
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$tmp = "$env:TEMP\eu4wem_$([System.IO.Path]::GetRandomFileName()).ogg"
Write-Host "Encoding 48kHz stereo..."
& ffmpeg -y -i $OggPath -ar 48000 -ac 2 -c:a libvorbis -q:a 6 $tmp 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "ffmpeg failed"; exit 1 }

Write-Host "Building WEM..."
[OggToWem]::Convert($tmp, $WemPath)
Remove-Item $tmp -EA SilentlyContinue

$sw.Stop()
$sz = (Get-Item $WemPath).Length
Write-Host "Done in $($sw.ElapsedMilliseconds)ms - WEM: $WemPath ($sz bytes)"
Write-Host "Launch EU5 and check if maintheme plays"
