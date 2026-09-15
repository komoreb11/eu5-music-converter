#Requires -Version 5.1
<#
.SYNOPSIS
    EU4 Soundtrack for EU5 - Auto Setup & Launcher
.DESCRIPTION
    Checks and converts missing EU4 tracks to WEM format, then launches EU5.
    No Python, no Wwise required. Uses ffmpeg only (v2).
.NOTES
    Steam launch option:
    powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\EU4_Soundtrack_Setup.ps1" -LaunchCmd "%COMMAND%"
    
    Or self-updating from GitHub:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr 'https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/EU4_Soundtrack_Setup.ps1' -OutFile '$env:TEMP\eu4snd.ps1'; & '$env:TEMP\eu4snd.ps1' -LaunchCmd '%COMMAND%'"
#>

param([string]$LaunchCmd = "")

# Refresh PATH so winget-installed tools (ffmpeg etc.) are found
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path","User")

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "EU4 Soundtrack Setup"

# --- CONFIG ------------------------------------------------
# Auto-detect eu4_soundtrack Workshop mod via Steam registry + libraryfolders.vdf
$ModDir = $null
$steamLibPaths = @()
$steamRoot = $null
try { $steamRoot = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -EA Stop).SteamPath -replace '/','\\' } catch {}
if (-not $steamRoot) {
    try { $steamRoot = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -EA Stop).InstallPath } catch {}
}
if ($steamRoot -and (Test-Path $steamRoot)) {
    $steamLibPaths += $steamRoot
    $vdf = "$steamRoot\steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
        Get-Content $vdf | Select-String '"path"' | ForEach-Object {
            if ($_ -match '"path"\s+"([^"]+)"') { $steamLibPaths += $Matches[1] -replace '\\\\','\\' }
        }
    }
}
foreach ($lib in $steamLibPaths) {
    $wBase = "$lib\steamapps\workshop\content\3450310"
    if (-not (Test-Path $wBase)) { continue }
    foreach ($wDir in (Get-ChildItem $wBase -Directory -EA SilentlyContinue)) {
        $meta = "$($wDir.FullName)\.metadata\metadata.json"
        if (Test-Path $meta) {
            $json = Get-Content $meta -Raw -EA SilentlyContinue
            if ($json -like '*"eu4_soundtrack"*') { $ModDir = $wDir.FullName; break }
        }
    }
    if ($ModDir) { break }
}
if (-not $ModDir) {
    Write-Host "[X]  EU4 Soundtrack mod not found in Steam Workshop. Subscribe to the mod first." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}
$BanksDir  = "$ModDir\loading_screen\sound\banks\windows"
$MediaDir  = "$BanksDir\Media"
$TmpDir    = "$env:TEMP\eu4snd_v2"
$CacheDll  = "$env:TEMP\eu4wem_cache\OggToWem_v6.dll"
$PcbPath   = "$env:TEMP\eu4wem_cache\packed_codebooks.bin"
$GitHubRaw = "https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main"

# --- COMPILE OGG->WEM CONVERTER (once, cached as DLL) ------
if (-not (Test-Path $CacheDll)) {
    New-Item -ItemType Directory -Force (Split-Path $CacheDll) | Out-Null
    Add-Type -TypeDefinition @'
using System; using System.IO; using System.Collections.Generic;

public class OggToWem {
    class BR {
        byte[] d; int pos;
        public BR(byte[] data){d=data;pos=0;}
        public int Read(int n){int v=0;for(int i=0;i<n;i++){int b=pos>>3,bt=pos&7;v|=((d[b]>>bt)&1)<<i;pos++;}return v;}
        public int Rem{get{return d.Length*8-pos;}}
    }
    class BW {
        List<byte> buf=new List<byte>();int cur=0,nb=0;
        public void Write(int v,int n){for(int i=0;i<n;i++){cur|=((v>>i)&1)<<nb;nb++;if(nb==8){buf.Add((byte)cur);cur=0;nb=0;}}}
        public byte[] Flush(){if(nb>0)buf.Add((byte)cur);return buf.ToArray();}
    }
    static int ILog(int x){if(x==0)return 0;int n=0;while(x>0){n++;x>>=1;}return n;}

    // Read one std Vorbis codebook, return canonical bytes for lookup
    static byte[] ReadCanonicalCb(BR br){
        var bw=new BW();
        int sync=br.Read(24); if(sync!=0x564342) throw new Exception("Bad codebook sync");
        int dims=br.Read(16),entries=br.Read(24);
        bw.Write(sync,24);bw.Write(dims,16);bw.Write(entries,24);
        int ordered=br.Read(1);bw.Write(ordered,1);
        if(ordered==1){
            int il=br.Read(5);bw.Write(il,5);int ce=0;
            while(ce<entries){int n=ILog(entries-ce);int c=br.Read(n);bw.Write(c,n);ce+=c;}
        } else {
            int sparse=br.Read(1);bw.Write(sparse,1);
            for(int i=0;i<entries;i++){
                bool present=true;
                if(sparse==1){int p=br.Read(1);bw.Write(p,1);present=(p==1);}
                if(present){int l=br.Read(5);bw.Write(l,5);}
            }
        }
        int lt=br.Read(4);bw.Write(lt,4);
        if(lt==1){
            bw.Write(br.Read(32),32);bw.Write(br.Read(32),32);
            int vl=br.Read(4);bw.Write(vl,4);bw.Write(br.Read(1),1);
            int qv=1;while(true){long a=1;for(int i=0;i<dims;i++)a*=qv;if(a>=entries)break;qv++;}
            for(int i=0;i<qv;i++)bw.Write(br.Read(vl+1),vl+1);
        }
        return bw.Flush();
    }

    // Decode one packed codebook (wwise inline) -> canonical bytes
    static byte[] DecodePcb(BR br){
        var bw=new BW();
        int dims=br.Read(4),entries=br.Read(14);
        bw.Write(0x564342,24);bw.Write(dims,16);bw.Write(entries,24);
        int ordered=br.Read(1);bw.Write(ordered,1);
        if(ordered==1){
            int il=br.Read(5);bw.Write(il,5);int ce=0;
            while(ce<entries){int n=ILog(entries-ce);int c=br.Read(n);bw.Write(c,n);ce+=c;}
        } else {
            int cwll=br.Read(3),sparse=br.Read(1);bw.Write(sparse,1);
            for(int i=0;i<entries;i++){
                bool present=true;
                if(sparse==1){int p=br.Read(1);bw.Write(p,1);present=(p==1);}
                if(present){int l=br.Read(cwll);bw.Write(l,5);}
            }
        }
        int lt=br.Read(1);bw.Write(lt,4);
        if(lt==1){
            bw.Write(br.Read(32),32);bw.Write(br.Read(32),32);
            int vl=br.Read(4);bw.Write(vl,4);bw.Write(br.Read(1),1);
            int qv=1;while(true){long a=1;for(int i=0;i<dims;i++)a*=qv;if(a>=entries)break;qv++;}
            for(int i=0;i<qv;i++)bw.Write(br.Read(vl+1),vl+1);
        }
        return bw.Flush();
    }

    // Build lookup: canonical_bytes_base64 -> packed_codebook_id
    static Dictionary<string,int> BuildLookup(string pcbPath){
        var pcb=File.ReadAllBytes(pcbPath);
        int offTableOff=BitConverter.ToInt32(pcb,pcb.Length-4);
        int cbCount=(pcb.Length-4-offTableOff)/4;
        var offsets=new int[cbCount+1];
        for(int i=0;i<cbCount;i++) offsets[i]=BitConverter.ToInt32(pcb,offTableOff+i*4);
        offsets[cbCount]=offTableOff;
        var lookup=new Dictionary<string,int>();
        for(int i=0;i<cbCount;i++){
            try{
                int sz=offsets[i+1]-offsets[i];
                var cb=new byte[sz]; Buffer.BlockCopy(pcb,offsets[i],cb,0,sz);
                var canonical=DecodePcb(new BR(cb));
                var key=System.Convert.ToBase64String(canonical);
                if(!lookup.ContainsKey(key)) lookup[key]=i;
            } catch{}
        }
        return lookup;
    }

    // Convert remaining setup section: floor/residue/mapping/mode
    // Removes fields Wwise omits, compresses residue_type 16->2 bits
    static void ConvertRemainingSetup(BR br, BW bw, int channels,
                                      out int modeBitsOut, out bool[] modeBlockflagOut){
        // ── TIME DOMAIN: Wwise omits entirely (hardcodes 0) ────────────────
        int tc=br.Read(6);                  // read time_count_m1 from std Vorbis
        for(int i=0;i<=tc;i++) br.Read(16); // skip time_type values (not written to Wwise)

        // ── FLOORS ─────────────────────────────────────────────────────────
        int fc=br.Read(6); bw.Write(fc,6); // floor_count_m1
        for(int i=0;i<=fc;i++){
            br.Read(16); // floor_type: skip (Wwise omits, always 1)
            // floor type 1 config
            int parts=br.Read(5); bw.Write(parts,5);
            var partClass=new int[parts];
            int maxClass=-1;
            for(int j=0;j<parts;j++){
                partClass[j]=br.Read(4); bw.Write(partClass[j],4);
                if(partClass[j]>maxClass) maxClass=partClass[j];
            }
            var classDims=new int[maxClass+1];
            for(int j=0;j<=maxClass;j++){
                int dims_m1=br.Read(3); bw.Write(dims_m1,3);
                classDims[j]=dims_m1+1;
                int subs=br.Read(2); bw.Write(subs,2);
                if(subs!=0){int mb=br.Read(8);bw.Write(mb,8);}
                for(int k=0;k<(1<<subs);k++){bw.Write(br.Read(8),8);} // same format in both: book+1, 0=no book
            }
            int mult_m1=br.Read(2); bw.Write(mult_m1,2);
            int rangebits=br.Read(4); bw.Write(rangebits,4);
            for(int j=0;j<parts;j++){
                for(int k=0;k<classDims[partClass[j]];k++){
                    int x=br.Read(rangebits); bw.Write(x,rangebits);
                }
            }
        }
        // ── RESIDUES ───────────────────────────────────────────────────────
        int rc=br.Read(6); bw.Write(rc,6); // residue_count_m1
        for(int i=0;i<=rc;i++){
            int rt=br.Read(16); bw.Write(rt,2); // residue_type: 16->2 bits
            // copy residue config
            bw.Write(br.Read(24),24); // begin
            bw.Write(br.Read(24),24); // end
            bw.Write(br.Read(24),24); // partition_size_m1
            int cls_m1=br.Read(6); bw.Write(cls_m1,6);
            bw.Write(br.Read(8),8);  // classbook
            int cls=cls_m1+1;
            var cascade=new int[cls];
            for(int j=0;j<cls;j++){
                int lb=br.Read(3); bw.Write(lb,3);
                int bit=br.Read(1); bw.Write(bit,1);
                int hb=0; if(bit==1){hb=br.Read(5);bw.Write(hb,5);}
                cascade[j]=lb|(hb<<3);
            }
            for(int j=0;j<cls;j++){
                for(int k=0;k<8;k++){
                    if((cascade[j]&(1<<k))!=0){bw.Write(br.Read(8),8);}
                }
            }
        }
        // ── MAPPINGS ───────────────────────────────────────────────────────
        int mc=br.Read(6); bw.Write(mc,6); // mapping_count_m1: both std Vorbis and Wwise use 6 bits
        for(int i=0;i<=mc;i++){
            br.Read(16); // mapping_type: skip (always 0)
            int sf=br.Read(1); bw.Write(sf,1);
            int submaps=1;
            if(sf==1){int sm=br.Read(4);bw.Write(sm,4);submaps=sm+1;}
            int sqpf=br.Read(1); bw.Write(sqpf,1);
            if(sqpf==1){
                int cs_m1=br.Read(8); bw.Write(cs_m1,8);
                int cs=cs_m1+1;
                int cbits=ILog(channels-1);
                for(int j=0;j<cs;j++){bw.Write(br.Read(cbits),cbits);bw.Write(br.Read(cbits),cbits);}
            }
            br.Read(2); bw.Write(0,2); // reserved: always 0 in Wwise
            if(submaps>1){for(int j=0;j<channels;j++){bw.Write(br.Read(4),4);}}
            for(int j=0;j<submaps;j++){
                bw.Write(br.Read(8),8); // time_config
                bw.Write(br.Read(8),8); // floor
                bw.Write(br.Read(8),8); // residue
            }
        }
        // ── MODES ──────────────────────────────────────────────────────────
        int modc=br.Read(6); bw.Write(modc,6);
        int modeCount=modc+1;
        var blockflags=new bool[modeCount];
        for(int i=0;i<modeCount;i++){
            int bf=br.Read(1); bw.Write(bf,1);
            blockflags[i]=(bf!=0);
            br.Read(16); br.Read(16); // windowtype, transformtype: skip
            bw.Write(br.Read(8),8); // mapping
        }
        bw.Write(1,1); // framing bit
        modeBitsOut=ILog(modeCount-1);
        modeBlockflagOut=blockflags;
    }

    // Transform standard Vorbis audio packet -> Wwise modified packet
    // Removes: 1-bit packet type, and 2 window bits for long-mode packets
    static byte[] ToModifiedPacket(byte[] pkt, int modeBits, bool[] modeBlockflag){
        if(pkt==null||pkt.Length==0) return pkt;
        var br=new BR(pkt); var bw=new BW();
        br.Read(1); // skip packet_type bit (always 0 for audio)
        int modeNum=(modeBits>0)?br.Read(modeBits):0;
        bool isLong=modeBlockflag!=null&&modeNum<modeBlockflag.Length&&modeBlockflag[modeNum];
        if(isLong&&br.Rem>=2){br.Read(1);br.Read(1);} // skip prev/next window bits
        if(modeBits>0) bw.Write(modeNum,modeBits);
        // copy all remaining bits verbatim
        while(br.Rem>0){int n=Math.Min(br.Rem,32);bw.Write(br.Read(n),n);}
        return bw.Flush();
    }

    // Convert std Vorbis setup -> external packed codebook IDs + rest verbatim
    // Also extracts mode info for packet transformation
    static byte[] SetupToExternal(byte[] st, Dictionary<string,int> lookup, int channels,
                                   out int modeBits, out bool[] modeBlockflag){
        var br=new BR(st); var bw=new BW();
        br.Read(56); // skip '05 vorbis'
        int cbc=br.Read(8); bw.Write(cbc,8);
        for(int i=0;i<=cbc;i++){
            var canonical=ReadCanonicalCb(br);
            var key=System.Convert.ToBase64String(canonical);
            int id;
            if(!lookup.TryGetValue(key,out id)) throw new Exception("Codebook "+i+" not in packed_codebooks");
            bw.Write(id,10);
        }
        // Convert remaining setup: floor/residue/mapping/mode
        // Wwise omits floor_type, mapping_type, mode windowtype/transformtype
        // Wwise stores residue_type as 2 bits instead of 16
        ConvertRemainingSetup(br,bw,channels,out modeBits,out modeBlockflag);
        return bw.Flush();
    }

    // OGG parser
    struct R{public List<byte[]> P;public long S;}
    static R Parse(byte[] d){
        var r=new R{P=new List<byte[]>()};
        int pos=0;byte[] buf=null;int bl=0;
        while(pos<=d.Length-27){
            if(d[pos]!=79||d[pos+1]!=103||d[pos+2]!=103||d[pos+3]!=83) break;
            long g=BitConverter.ToInt64(d,pos+6);if(g>0)r.S=g;
            int ns=d[pos+26],dp=pos+27+ns;
            for(int i=0;i<ns;i++){
                int sz=d[pos+27+i];
                if(bl+sz>(buf==null?0:buf.Length)){var nb=new byte[Math.Max(bl+sz,bl*2+256)];if(buf!=null)Buffer.BlockCopy(buf,0,nb,0,bl);buf=nb;}
                Buffer.BlockCopy(d,dp,buf,bl,sz);bl+=sz;dp+=sz;
                if(sz<255){var p=new byte[bl];Buffer.BlockCopy(buf,0,p,0,bl);r.P.Add(p);bl=0;}
            }
            pos=dp;
        }
        if(bl>0){var p=new byte[bl];Buffer.BlockCopy(buf,0,p,0,bl);r.P.Add(p);}
        return r;
    }
    static void W16(BinaryWriter w,int v){w.Write((ushort)v);}
    static void W32(BinaryWriter w,long v){w.Write((uint)v);}

    public static string Convert(string ogg,string wem,string pcbPath){
        try{
            var lookup=BuildLookup(pcbPath);
            var r=Parse(File.ReadAllBytes(ogg));
            if(r.P.Count<4) return "Too few packets: "+r.P.Count;
            var id=r.P[0];int ch=id[11],sr=BitConverter.ToInt32(id,12),bs=id[28];
            int bs0=bs&0xF,bs1=(bs>>4)&0xF;
            int modeBits; bool[] modeBlockflag;
            byte[] setup=SetupToExternal(r.P[2],lookup,ch,out modeBits,out modeBlockflag);
            // Collect audio packets, transform to Wwise modified format, build seek table
            var audioPkts=new System.Collections.Generic.List<byte[]>();
            int mx=0;
            for(int i=3;i<r.P.Count;i++){
                var p=ToModifiedPacket(r.P[i],modeBits,modeBlockflag);
                audioPkts.Add(p);if(p.Length>mx)mx=p.Length;
            }
            var seekEntries=new System.Collections.Generic.List<uint>();
            uint apos=0;
            foreach(var p in audioPkts){
                if(seekEntries.Count==0||apos-seekEntries[seekEntries.Count-1]>=2048)
                    seekEntries.Add(apos);
                apos+=(uint)(2+p.Length);
            }
            byte[] seekTable=new byte[seekEntries.Count*4];
            for(int i=0;i<seekEntries.Count;i++)
                BitConverter.GetBytes(seekEntries[i]).CopyTo(seekTable,i*4);
            // Layout: [seek_table][size_prefix(2)][setup][audio]
            long seekSz=seekTable.Length;
            long audioStart=seekSz+2+setup.Length;
            using(var ms=new MemoryStream(seekTable.Length+(int)audioStart+audioPkts.Count*512)){
                var bw=new BinaryWriter(ms);
                bw.Write(seekTable);
                W16(bw,setup.Length);bw.Write(setup);
                foreach(var p in audioPkts){W16(bw,p.Length);bw.Write(p);}
                long de=ms.Position;byte[] data=ms.ToArray();
                using(var fe=new MemoryStream(48)){
                    var fw=new BinaryWriter(fe);
                    fw.Write(new byte[]{0,0,2,0x31,0,0});
                    W32(fw,r.S);W32(fw,audioStart);W32(fw,de);W16(fw,0);W16(fw,0);
                    W32(fw,seekSz);W32(fw,audioStart);
                    W16(fw,mx);W16(fw,0);W32(fw,(1<<bs1)*ch*2);W32(fw,(1<<bs1)*ch*4);W32(fw,0);
                    fw.Write((byte)bs0);fw.Write((byte)bs1);
                    byte[] ex=fe.ToArray();
                    // Write to .part first: an interrupted run must not leave a truncated .wem that counts as done
                    using(var f=new FileStream(wem+".part",FileMode.Create,FileAccess.Write,FileShare.None,65536)){
                        var ww=new BinaryWriter(f);
                        ww.Write(new byte[]{0x52,0x49,0x46,0x46});
                        W32(ww,4+8+66+8+16+8+data.Length);
                        ww.Write(new byte[]{0x57,0x41,0x56,0x45,0x66,0x6D,0x74,0x20});
                        W32(ww,66);W16(ww,0xFFFF);W16(ww,ch);W32(ww,sr);W32(ww,sr*ch*2);W16(ww,0);W16(ww,0);W16(ww,48);
                        ww.Write(ex);
                        ww.Write(new byte[]{0x68,0x61,0x73,0x68});W32(ww,16);ww.Write(new byte[16]);
                        ww.Write(new byte[]{0x64,0x61,0x74,0x61});W32(ww,data.Length);ww.Write(data);
                    }
                    if(File.Exists(wem))File.Delete(wem);
                    File.Move(wem+".part",wem);
                }
            }
            return "ok";
        } catch(Exception e){
            try{File.Delete(wem+".part");}catch{}
            return e.GetType().Name+": "+e.Message;
        }
    }
}

// Builds the mod's sound banks on the player's PC from the installed EU5 music bank and the WEM
// files that exist, so updates only need this script. A shipped eu4_soundtrack_music.bnk listed
// all tracks: players without some DLCs got silence whenever a playlist picked a missing track,
// and its copy of EU5's music objects went stale with every EU5 patch.
// Mirrors build_mod.py - keep both in sync.
public static class BankBuilder {
    const int Item=30; // AkMusicRanSeqPlaylistItem
    static uint U32(byte[] b,int o){return BitConverter.ToUInt32(b,o);}
    static void Put32(byte[] b,int o,uint v){b[o]=(byte)v;b[o+1]=(byte)(v>>8);b[o+2]=(byte)(v>>16);b[o+3]=(byte)(v>>24);}

    // FNV-1, same as build_mod.make_id
    public static uint Fnv(string s){
        unchecked{uint h=2166136261;foreach(char c in s.ToLowerInvariant()){h*=16777619;h^=(byte)c;}return h;}
    }

    static List<KeyValuePair<string,byte[]>> ReadChunks(byte[] b){
        var r=new List<KeyValuePair<string,byte[]>>();int pos=0;
        while(pos+8<=b.Length){
            string tag=System.Text.Encoding.ASCII.GetString(b,pos,4);int sz=(int)U32(b,pos+4);
            if(pos+8+sz>b.Length)throw new Exception("truncated "+tag+" chunk");
            var d=new byte[sz];Buffer.BlockCopy(b,pos+8,d,0,sz);
            r.Add(new KeyValuePair<string,byte[]>(tag,d));pos+=8+sz;
        }
        return r;
    }
    static byte[] GetChunk(List<KeyValuePair<string,byte[]>> chunks,string tag){
        foreach(var c in chunks)if(c.Key==tag)return c.Value;
        return null;
    }
    static void WriteChunk(Stream s,string tag,byte[] d){
        s.Write(System.Text.Encoding.ASCII.GetBytes(tag),0,4);s.Write(BitConverter.GetBytes((uint)d.Length),0,4);s.Write(d,0,d.Length);
    }
    // HIRC objects as raw [type][size][body], body starts with the object ID
    static List<byte[]> ReadObjects(byte[] hirc){
        var r=new List<byte[]>();uint n=U32(hirc,0);int p=4;
        for(uint i=0;i<n;i++){int sz=(int)U32(hirc,p+1);var o=new byte[5+sz];Buffer.BlockCopy(hirc,p,o,0,5+sz);r.Add(o);p+=5+sz;}
        return r;
    }
    static bool WriteIfChanged(string path,byte[] data){
        if(File.Exists(path)){
            var old=File.ReadAllBytes(path);
            if(old.Length==data.Length){int i=0;while(i<data.Length&&old[i]==data[i])i++;if(i==data.Length)return false;}
        }
        File.WriteAllBytes(path+".part",data);
        if(File.Exists(path))File.Delete(path);
        File.Move(path+".part",path);
        return true;
    }

    // RIFF size must match the file length: a truncated WEM (e.g. interrupted conversion) plays as silence.
    // Format tag 0xFFFF = Vorbis WEM from this script; old Wwise-authored WEMs (v1.0) get converted again.
    public static bool IsValidWem(string path){
        try{
            if(!File.Exists(path))return false;
            using(var f=File.OpenRead(path)){
                var h=new byte[22];
                if(f.Length<22||f.Read(h,0,22)!=22)return false;
                return h[0]=='R'&&h[1]=='I'&&h[2]=='F'&&h[3]=='F'&&h[8]=='W'&&h[9]=='A'&&h[10]=='V'&&h[11]=='E'
                    &&(long)U32(h,4)+8==f.Length&&h[20]==0xFF&&h[21]==0xFF;
            }
        } catch(Exception){return false;}
    }

    static int SubtreeEnd(List<byte[]> items,int k){
        long pending=1;
        while(pending>0){if(k>=items.Count)return -1;pending+=(long)U32(items[k],8)-1;k++;}
        return k;
    }
    static byte[] NewItem(uint seg,uint itemId,uint children,int rsType,int avoid,byte usingWeight,byte shuffle){
        var it=new byte[Item];
        Put32(it,0,seg);Put32(it,4,itemId);Put32(it,8,children);Put32(it,12,(uint)rsType);
        it[16]=1;Put32(it,22,50000);it[26]=(byte)avoid;it[27]=(byte)(avoid>>8);it[28]=usingWeight;it[29]=shuffle;
        return it;
    }
    // Mirrors build_mod.insert_playlist_leaves - keep both in sync
    static byte[] InsertLeaves(byte[] content,uint containerId,List<uint> segs,bool joinPool){
        int off=-1;List<byte[]> items=null;
        for(int o=content.Length-4-Item;o>=0&&items==null;o--){
            long n=U32(content,o);
            if(n==0||o+4+n*Item!=content.Length)continue;
            var list=new List<byte[]>();
            for(int k=0;k<n;k++){var it=new byte[Item];Buffer.BlockCopy(content,o+4+k*Item,it,0,Item);list.Add(it);}
            if(SubtreeEnd(list,0)==n){off=o;items=list;}
        }
        if(items==null)return null;
        int cnt=segs.Count;
        var leaves=new List<byte[]>();
        for(int i=0;i<cnt;i++)leaves.Add(NewItem(segs[i],segs[i]^0xC0FFEE00u^(uint)i,0,-1,0,0,0));
        var group=NewItem(0,Fnv("eu4_soundtrack_group_"+containerId),(uint)cnt,3,Math.Min(cnt-1,cnt/2),1,1);
        byte[] first=items.Count>1?items[1]:null;
        // Culture playlists restart from the top whenever the music switch returns to them:
        // offer EU4 tracks at the first random pool (the soloist pieces), where the cycle starts
        int pool=-1;
        for(int k=0;k<items.Count&&pool<0;k++){int rs=(int)U32(items[k],12);if(U32(items[k],8)>=2&&(rs==2||rs==3))pool=k;}
        if(joinPool&&first!=null&&U32(first,8)>0&&((int)U32(first,12)==2||(int)U32(first,12)==3)&&SubtreeEnd(items,1)==2+U32(first,8)){
            // WAR/PEACE: the root's first child is a flat random pool - join it
            int end=2+(int)U32(first,8);
            Put32(first,8,U32(first,8)+(uint)cnt);
            items.InsertRange(end,leaves);
        } else if(pool>=0){
            // Random pick of "EU5 soloist piece" or "EU4 track": EU4 gets 50%, but no more than one piece per EU4 track
            uint m=U32(items[pool],8);
            var choice=NewItem(0,Fnv("eu4_soundtrack_choice_"+containerId),2,3,0,1,0);
            Put32(choice,22,U32(items[pool],22));
            Put32(items[pool],22,50000);
            Put32(group,22,(uint)(50000L*Math.Min((uint)cnt,m)/m));
            int end=SubtreeEnd(items,pool);
            items.Insert(end,group);
            items.InsertRange(end+1,leaves);
            items.Insert(pool,choice);
        } else {
            // No random pool: one random pick of EU4 tracks as the last step of the root sequence
            Put32(items[0],8,U32(items[0],8)+1);
            items.Add(group);
            items.AddRange(leaves);
        }
        var r=new byte[off+4+items.Count*Item];
        Buffer.BlockCopy(content,0,r,0,off);Put32(r,off,(uint)items.Count);
        for(int k=0;k<items.Count;k++)Buffer.BlockCopy(items[k],0,r,off+4+k*Item,Item);
        return r;
    }
    static byte[] Hex(string h){var r=new byte[h.Length/2];for(int i=0;i<r.Length;i++)r[i]=System.Convert.ToByte(h.Substring(2*i,2),16);return r;}
    static void PutF64(byte[] b,int o,double v){Buffer.BlockCopy(BitConverter.GetBytes(v),0,b,o,8);}
    static byte[] Hirc(byte type,uint id,byte[] content){
        var r=new byte[9+content.Length];r[0]=type;Put32(r,1,(uint)(4+content.Length));Put32(r,5,id);
        Buffer.BlockCopy(content,0,r,9,content.Length);return r;
    }

    // Bank IDs/GUIDs as in build_mod.py: crc32("eu4_soundtrack_music"/"eu4_soundtrack_media"), md5 of their names
    const uint MusicBankId=0x3e708754, MediaBankId=0x990e0412, BankVersion=150;
    static readonly byte[] MusicGuid=Hex("ae6da5b859d619f42aa763976cc0e0d1"), MediaGuid=Hex("b2a234ccd3aa95e28ce3432436c3c6ec");
    // WAR/PEACE: switch 0x1cb30afd on PlayerAtWar (True -> 0x290f1591, False -> 0x3de374bf)
    const uint WarPlaylist=0x290f1591, PeacePlaylist=0x3de374bf;
    // Culture: switch 0x0e3915aa on PlayerCulturePrimary
    static uint CulturePlaylist(string culture){
        switch(culture){
            case "european": return 0x172E4EBA;       case "east_asian": return 0x2AE87B0D;
            case "african": return 0x2D1FE56A;        case "middle_east": return 0x177DFABD;
            case "indian": return 0x014173A7;         case "north_american": return 0x0847DCF1;
            case "south_american": return 0x360B858E; default: return 0;
        }
    }
    // Templates from EU5 objects, see build_mod.make_music_track / make_music_segment
    const string TrackTpl="00010000000100040001555f6625c2150000000100000000000000555f6625"+
        "00000000000000000000000000000000000000000000000000000000"+
        "1357ba37a0d8bc4001000000000000000000000000000000"+
        "ec74d200000000000000000000000100000000000000000064000000";
    const string SegmentTpl="00000000000000000024e85a3b0000000000000000000001000000000000000001000000"+
        "ca670435"+
        "0000000000408f4000000000000000000000f0420404000000000045c85fb343d30741"+
        "0200000012df980200000000000000000048d6bb5b"+
        "45c85fb343d30741"+
        "00";
    static byte[] MusicTrack(uint id,uint wem,uint prefetch,double durMs,uint segment){
        var t=Hex(TrackTpl);
        Put32(t,10,wem);Put32(t,14,prefetch);Put32(t,27,wem);
        PutF64(t,35,0.0);PutF64(t,43,0.0);PutF64(t,51,0.0);PutF64(t,59,durMs);Put32(t,83,segment);
        return Hirc(11,id,t);
    }
    static byte[] MusicSegment(uint id,uint track,double durMs,uint parent){
        var t=Hex(SegmentTpl);
        if(parent!=0)Put32(t,9,parent);
        Put32(t,36,track);PutF64(t,67,durMs);PutF64(t,96,durMs);
        return Hirc(10,id,t);
    }
    static uint PlaylistOf(string key,string culture){
        return key=="war"?WarPlaylist:key=="pce"?PeacePlaylist:CulturePlaylist(culture);
    }

    // eu4_soundtrack_music.bnk = installed EU5 sb_music_logic.bnk + EU4 objects of tracks whose WEM exists.
    // tracks: "EventName|mood|culture" (mood war/peace/neutral/discovery, culture may be empty), in build_mod.TRACKS order
    public static string BuildMusic(string eu5BankPath,string[] tracks,string mediaDir,string outPath){
        try{
            var eu5=ReadChunks(File.ReadAllBytes(eu5BankPath));
            byte[] eu5Bkhd=GetChunk(eu5,"BKHD"),eu5Hirc=GetChunk(eu5,"HIRC");
            if(eu5Bkhd==null||eu5Hirc==null||eu5Bkhd.Length<24)return "error: unexpected EU5 bank layout";
            if(U32(eu5Bkhd,0)!=BankVersion)return "error: EU5 sound bank version "+U32(eu5Bkhd,0)+" is not supported, mod update required";

            var modObjs=new List<byte[]>();var ins=new Dictionary<uint,List<uint>>();
            int present=0,absent=0;
            foreach(var line in tracks){
                var f=line.Split('|');string ev=f[0],mood=f[1],culture=f.Length>2?f[2]:"";
                uint wem=Fnv(ev+"_wem");string path=Path.Combine(mediaDir,wem+".wem");
                if(!IsValidWem(path)){absent++;continue;}
                present++;
                // Duration from the WEM: dwTotalPCMFrames (fmt extra +6) / sample rate
                byte[] head;long len;
                using(var fs=File.OpenRead(path)){len=fs.Length;head=new byte[(int)Math.Min(len,65536)];fs.Read(head,0,head.Length);}
                double dur=0.0;
                for(int pos=12;pos<head.Length-8;){
                    int sz=(int)U32(head,pos+4);
                    if(head[pos]=='f'&&head[pos+1]=='m'&&head[pos+2]=='t'&&head[pos+3]==' '){
                        dur=(double)U32(head,pos+8+24)/Math.Max(U32(head,pos+8+4),1u);break;
                    }
                    pos+=8+sz;
                }
                double durMs=Math.Max(1.0,dur)*1000.0;
                uint pre=(uint)Math.Min(len,8192);
                uint tid=Fnv(ev+"_track"),sid=Fnv(ev+"_seg"),aid=Fnv(ev+"_action"),uid=Fnv(ev+"_setup");
                // Music Player chain
                modObjs.Add(MusicTrack(tid,wem,pre,durMs,sid));
                modObjs.Add(MusicSegment(sid,tid,durMs,0));
                var setup=new byte[9];setup[0]=0x03;setup[1]=0x21;Put32(setup,2,0xdccd55a7);
                modObjs.Add(Hirc(3,uid,setup));
                var play=new byte[18];play[0]=0x03;play[1]=0x04;Put32(play,2,sid);Buffer.BlockCopy(Hex("00000004a1c7709300000000"),0,play,6,12);
                modObjs.Add(Hirc(3,aid,play));
                var evt=new byte[9];evt[0]=2;Put32(evt,1,uid);Put32(evt,5,aid);
                modObjs.Add(Hirc(4,Fnv(ev),evt));
                // Dynamic playlists: suffix + playlist
                var dyn=new List<string>();
                if(mood=="war")dyn.Add("|war");else if(mood=="peace")dyn.Add("|pce");else{dyn.Add("_war|war");dyn.Add("_pce|pce");}
                if(CulturePlaylist(culture)!=0)dyn.Add("_cult|cult");
                foreach(var d in dyn){
                    var sp=d.Split('|');uint pl=PlaylistOf(sp[1],culture);
                    uint ds=Fnv(ev+sp[0]+"_dynseg"),dt=Fnv(ev+sp[0]+"_dyn_track");
                    modObjs.Add(MusicTrack(dt,wem,pre,durMs,ds));
                    modObjs.Add(MusicSegment(ds,dt,durMs,pl));
                    List<uint> l;if(!ins.TryGetValue(pl,out l)){l=new List<uint>();ins[pl]=l;}
                    l.Add(ds);
                }
            }

            var objs=new List<byte[]>();var patched=new HashSet<uint>();
            foreach(var o in ReadObjects(eu5Hirc)){
                uint id=U32(o,5);List<uint> segs;
                if(o[0]==13&&ins.TryGetValue(id,out segs)){
                    var content=new byte[o.Length-9];Buffer.BlockCopy(o,9,content,0,content.Length);
                    var nc=InsertLeaves(content,id,segs,id==WarPlaylist||id==PeacePlaylist);
                    if(nc!=null){objs.Add(Hirc(13,id,nc));patched.Add(id);continue;}
                }
                objs.Add(o);
            }
            foreach(var id in ins.Keys)
                if(!patched.Contains(id))return "error: EU5 playlist "+id.ToString("x8")+" not found, mod update required";
            objs.AddRange(modObjs);

            var hirc=new MemoryStream();
            hirc.Write(BitConverter.GetBytes((uint)objs.Count),0,4);
            foreach(var o in objs)hirc.Write(o,0,o.Length);
            var bkhd=new byte[40];
            Buffer.BlockCopy(eu5Bkhd,0,bkhd,0,4);Put32(bkhd,4,MusicBankId);Buffer.BlockCopy(eu5Bkhd,8,bkhd,8,16);Buffer.BlockCopy(MusicGuid,0,bkhd,24,16);
            var bank=new MemoryStream();
            foreach(var c in eu5)WriteChunk(bank,c.Key,c.Key=="BKHD"?bkhd:c.Key=="HIRC"?hirc.ToArray():c.Value);
            bool changed=WriteIfChanged(outPath,bank.ToArray());
            return "ok "+present+" "+absent+" "+(changed?"updated":"unchanged");
        } catch(Exception e){return "error: "+e.Message;}
    }

    // eu4_soundtrack_media.bnk = first 8 KB (prefetch) of every WEM present, DIDX sorted by ID like Wwise does
    public static string BuildMedia(uint[] wemIds,string mediaDir,string outPath){
        try{
            var ids=new List<uint>(new HashSet<uint>(wemIds));ids.Sort();
            var didx=new MemoryStream();var data=new MemoryStream();int n=0;
            foreach(var id in ids){
                var p=Path.Combine(mediaDir,id+".wem");
                if(!IsValidWem(p))continue;
                byte[] pre;
                using(var f=File.OpenRead(p)){
                    pre=new byte[(int)Math.Min(f.Length,8192)];int got=0;
                    while(got<pre.Length){int k=f.Read(pre,got,pre.Length-got);if(k<=0)break;got+=k;}
                }
                while(data.Length%16!=0)data.WriteByte(0);
                didx.Write(BitConverter.GetBytes(id),0,4);
                didx.Write(BitConverter.GetBytes((uint)data.Length),0,4);
                didx.Write(BitConverter.GetBytes((uint)pre.Length),0,4);
                data.Write(pre,0,pre.Length);n++;
            }
            // BKHD as in build_mod.make_bank
            var bkhd=new byte[40];
            Put32(bkhd,0,BankVersion);Put32(bkhd,4,MediaBankId);Put32(bkhd,8,0x17705D3E);Put32(bkhd,12,0x10);Put32(bkhd,16,0x387C);
            Buffer.BlockCopy(MediaGuid,0,bkhd,24,16);
            var bank=new MemoryStream();
            WriteChunk(bank,"BKHD",bkhd);
            if(n>0){WriteChunk(bank,"DIDX",didx.ToArray());WriteChunk(bank,"DATA",data.ToArray());}
            bool changed=WriteIfChanged(outPath,bank.ToArray());
            return "ok "+n+" "+(changed?"updated":"unchanged");
        } catch(Exception e){return "error: "+e.Message;}
    }
}
'@ -OutputAssembly $CacheDll
}
Add-Type -Path $CacheDll

# --- oggenc2 (aoTuV) for floor type 1 Vorbis encoding ---
$OggEncPath = "$env:TEMP\eu4wem_cache\oggenc2.exe"
$FlacDll    = "$env:TEMP\eu4wem_cache\libFLAC.dll"
Add-Type -Assembly System.IO.Compression.FileSystem -EA SilentlyContinue

# --- TRACK LIST --------------------------------------------
# Format: EventName|SourceOgg|DlcDir|mood|culture - same order and data as build_mod.TRACKS
# mood: war/peace (one playlist) or neutral/discovery (both); culture: playlist of the culture group
$Tracks = @(
    "MusicPlayer_eu4_maintheme|maintheme.ogg||neutral|"
    "MusicPlayer_eu4_dehominisdignitate|dehominisdignitate.ogg||neutral|"
    "MusicPlayer_eu4_kingscourt|kingscourt.ogg||neutral|"
    "MusicPlayer_eu4_kingsinthenorth|kingsinthenorth.ogg||neutral|"
    "MusicPlayer_eu4_machiavelli|machiavelli.ogg||neutral|"
    "MusicPlayer_eu4_nighttime|nighttime.ogg||neutral|"
    "MusicPlayer_eu4_thestonemasons|thestonemasons.ogg||neutral|"
    "MusicPlayer_eu4_moodevent_thesnowiscoming|moodevent_thesnowiscoming.ogg||neutral|"
    "MusicPlayer_eu4_amongthepoor|amongthepoor.ogg||peace|"
    "MusicPlayer_eu4_commerceinthepeninsula|commerceinthepeninsula.ogg||peace|"
    "MusicPlayer_eu4_eire|eire.ogg||peace|european"
    "MusicPlayer_eu4_inthestreets|inthestreets.ogg||peace|"
    "MusicPlayer_eu4_mood_landinsight|mood_landinsight.ogg||peace|"
    "MusicPlayer_eu4_openseas|openseas.ogg||peace|"
    "MusicPlayer_eu4_thesoundofsummer|thesoundofsummer.ogg||peace|"
    "MusicPlayer_eu4_battleoflepanto|battleoflepanto.ogg||war|"
    "MusicPlayer_eu4_event_war_battleofbreitenfeld|event_war_battleofbreitenfeld.ogg||war|"
    "MusicPlayer_eu4_mykingdom|mykingdom.ogg||war|"
    "MusicPlayer_eu4_rideforthvictoriously|rideforthvictoriously.ogg||war|"
    "MusicPlayer_eu4_thestageisset|thestageisset.ogg||war|"
    "MusicPlayer_eu4_war_offtowar|war_offtowar.ogg||war|"
    "MusicPlayer_eu4_mood_discovery|mood_discovery.ogg||discovery|"
    "MusicPlayer_eu4_theageofdiscovery|theageofdiscovery.ogg||discovery|"
    "MusicPlayer_eu4_thegrandarmada|music/thegrandarmada.ogg|dlc013_songs_of_the_new_world|peace|european"
    "MusicPlayer_eu4_thehunt|music/thehunt.ogg|dlc013_songs_of_the_new_world|neutral|"
    "MusicPlayer_eu4_travelthenewworld|music/travelthenewworld.ogg|dlc013_songs_of_the_new_world|discovery|"
    "MusicPlayer_eu4_pdxmascarol|music/pdxmascarol.ogg|dlc014_songs_of_yuletide|neutral|"
    "MusicPlayer_eu4_rmp_a_new_way|music/A_new_way.ogg|dlc026_republican_music|neutral|"
    "MusicPlayer_eu4_rmp_diplomatic_awakening|music/Diplomatic_Awakening.ogg|dlc026_republican_music|peace|"
    "MusicPlayer_eu4_rmp_falalalan|music/Falalalan.ogg|dlc026_republican_music|neutral|"
    "MusicPlayer_eu4_rmp_introductions|music/Introductions.ogg|dlc026_republican_music|neutral|"
    "MusicPlayer_eu4_rmp_piano_concerto|music/Piano_Concerto_No_1000.ogg|dlc026_republican_music|neutral|"
    "MusicPlayer_eu4_sow_castles|music/sow_castles.ogg|dlc030_songs_of_war|neutral|"
    "MusicPlayer_eu4_sow_distress|music/sow_distress.ogg|dlc030_songs_of_war|war|"
    "MusicPlayer_eu4_sow_george_whitehead|music/sow_george_whitehead.ogg|dlc030_songs_of_war|war|"
    "MusicPlayer_eu4_sow_lautunno|music/sow_lautunno.ogg|dlc030_songs_of_war|war|"
    "MusicPlayer_eu4_sow_the_siege|music/sow_the_siege.ogg|dlc030_songs_of_war|war|"
    "MusicPlayer_eu4_gds_battleoflepanto|music/031_battleoflepanto.ogg|dlc031_guns_drums_and_steel|war|"
    "MusicPlayer_eu4_gds_kingscourt|music/031_kingscourt.ogg|dlc031_guns_drums_and_steel|neutral|"
    "MusicPlayer_eu4_gds_maintheme|music/031_maintheme.ogg|dlc031_guns_drums_and_steel|neutral|"
    "MusicPlayer_eu4_gds_rideforthvictoriously|music/031_rideforthvictoriously.ogg|dlc031_guns_drums_and_steel|war|"
    "MusicPlayer_eu4_gds_thestageisset|music/031_thestageisset.ogg|dlc031_guns_drums_and_steel|war|"
    "MusicPlayer_eu4_soe_asettlement|music/soe_asettlement.ogg|dlc036_songs_of_exploration|peace|"
    "MusicPlayer_eu4_soe_asettlement2|music/soe_asettlement2.ogg|dlc036_songs_of_exploration|peace|"
    "MusicPlayer_eu4_soe_canzonelabavara|music/soe_canzonelabavara.ogg|dlc036_songs_of_exploration|neutral|"
    "MusicPlayer_eu4_soe_redsun|music/soe_redsun.ogg|dlc036_songs_of_exploration|peace|"
    "MusicPlayer_eu4_soe_theconqueror|music/soe_theconqueror.ogg|dlc036_songs_of_exploration|peace|"
    "MusicPlayer_eu4_gds_eire|music/037_eire.ogg|dlc037_guns_drums_and_steel_volume_2|peace|european"
    "MusicPlayer_eu4_gds_mykingdom|music/037_mykingdom.ogg|dlc037_guns_drums_and_steel_volume_2|war|"
    "MusicPlayer_eu4_gds2_commerceinthepeninsula|music/037_commerceinthepeninsula.ogg|dlc037_guns_drums_and_steel_volume_2|neutral|"
    "MusicPlayer_eu4_gds2_theageofdiscovery|music/037_theageofdiscovery.ogg|dlc037_guns_drums_and_steel_volume_2|peace|"
    "MusicPlayer_eu4_gds2_thestonemasons|music/037_thestonemasons.ogg|dlc037_guns_drums_and_steel_volume_2|neutral|"
    "MusicPlayer_eu4_kairis_emperors_road|music/Emperors_Road.ogg|dlc044_kairis_soundtrack|neutral|east_asian"
    "MusicPlayer_eu4_kairis_forest_shade|music/Forest_Shade.ogg|dlc044_kairis_soundtrack|peace|"
    "MusicPlayer_eu4_kairis_jade_ambitions|music/Jade_Ambitions.ogg|dlc044_kairis_soundtrack|neutral|east_asian"
    "MusicPlayer_eu4_kairis_silken_path|music/Silken_Path.ogg|dlc044_kairis_soundtrack|neutral|east_asian"
    "MusicPlayer_eu4_kairis_takeda_sunrise|music/Takeda_Sunrise.ogg|dlc044_kairis_soundtrack|neutral|east_asian"
    "MusicPlayer_eu4_ksp2_eastern_fronts|music/ksp2_eastern_fronts.ogg|dlc059_kairis_soundtrack_part_2|war|east_asian"
    "MusicPlayer_eu4_ksp2_peace_for_generations|music/ksp2_peace_for_generations.ogg|dlc059_kairis_soundtrack_part_2|peace|east_asian"
    "MusicPlayer_eu4_ksp2_temple_ambitions|music/ksp2_temple_ambitions.ogg|dlc059_kairis_soundtrack_part_2|neutral|east_asian"
    "MusicPlayer_eu4_ksp2_the_grasslands_call|music/ksp2_the_grasslands_call.ogg|dlc059_kairis_soundtrack_part_2|discovery|"
    "MusicPlayer_eu4_ksp2_the_great_wall|music/ksp2_the_great_wall.ogg|dlc059_kairis_soundtrack_part_2|neutral|east_asian"
    "MusicPlayer_eu4_sormp_a_golden_sun_is_rising|music/sormp_A_Golden_Sun_is_Rising_Ambient.ogg|dlc063_songs_of_regency|peace|european"
    "MusicPlayer_eu4_sormp_for_honour_and_glory|music/sormp_For_Honour_and_Glory_War.ogg|dlc063_songs_of_regency|war|european"
    "MusicPlayer_eu4_sormp_our_destiny|music/sormp_Our_Destiny_Ambient.ogg|dlc063_songs_of_regency|peace|"
    "MusicPlayer_eu4_sormp_i_didnt_choose|music/sormp_I_didnt_choose_this_life_it_chose_me_Ambient.ogg|dlc063_songs_of_regency|neutral|"
    "MusicPlayer_eu4_rus_a_russian_heart|music/ruamp_a_russian_heart.ogg|dlc076_the_rus_awaken|neutral|european"
    "MusicPlayer_eu4_rus_following_the_volga|music/ruamp_following_the_volga.ogg|dlc076_the_rus_awaken|peace|european"
    "MusicPlayer_eu4_rus_iwans_dream|music/ruamp_iwans_dream.ogg|dlc076_the_rus_awaken|neutral|european"
    "MusicPlayer_eu4_kott_faith_restored|music/Faith_Restored.ogg|dlc081_kairis_soundtrack_3_ottoman_tunes|peace|middle_east"
    "MusicPlayer_eu4_kott_homebound|music/Homebound.ogg|dlc081_kairis_soundtrack_3_ottoman_tunes|peace|middle_east"
    "MusicPlayer_eu4_kott_peace_cannot_last|music/Peace_Cannot_Last.ogg|dlc081_kairis_soundtrack_3_ottoman_tunes|neutral|middle_east"
    "MusicPlayer_eu4_kott_sundered_hills|music/Sundered_Hills.ogg|dlc081_kairis_soundtrack_3_ottoman_tunes|neutral|middle_east"
    "MusicPlayer_eu4_kott_whispers_dark|music/Whispers_in_the_Dark.ogg|dlc081_kairis_soundtrack_3_ottoman_tunes|neutral|middle_east"
    "MusicPlayer_eu4_brit_alba|music/Alba.ogg|dlc089_rule_britannia_music_pack|neutral|european"
    "MusicPlayer_eu4_brit_battle_in_the_highlands|music/A_Battle_in_the_Highlands.ogg|dlc089_rule_britannia_music_pack|war|european"
    "MusicPlayer_eu4_brit_piper_lead_your_clansmen|music/Piper_Lead_Your_Clansmen.ogg|dlc089_rule_britannia_music_pack|war|european"
    "MusicPlayer_eu4_dharma_carnatic|music/Carnatic.ogg|dlc094_dharma_music|neutral|indian"
    "MusicPlayer_eu4_dharma_hindustani|music/Hindustani.ogg|dlc094_dharma_music|neutral|indian"
    "MusicPlayer_eu4_dharma_rajastani|music/Rajastani.ogg|dlc094_dharma_music|neutral|indian"
    "MusicPlayer_eu4_gc_birth_of_global_empire|music/birth_of_a_global_empire.ogg|dlc099_golden_century_music|neutral|european"
    "MusicPlayer_eu4_gc_conflict_in_the_caribbean|music/conflict_in_the_caribbean.ogg|dlc099_golden_century_music|war|european"
    "MusicPlayer_eu4_gc_march_on_granada|music/march_on_granada.ogg|dlc099_golden_century_music|war|european"
    "MusicPlayer_eu4_emp_empire_divided|music/anempiredivided.ogg|dlc105_emperor_music|neutral|european"
    "MusicPlayer_eu4_emp_birthplace_of_renaissance|music/birthplaceofrenaissance.ogg|dlc105_emperor_music|neutral|european"
    "MusicPlayer_eu4_emp_duality_of_faith|music/dualityoffaith.ogg|dlc105_emperor_music|neutral|"
    "MusicPlayer_eu4_na_american_soil|music/american_soil.ogg|dlc108_north_america_music|neutral|north_american"
    "MusicPlayer_eu4_na_cautious_preparation|music/cautious_preparation.ogg|dlc108_north_america_music|neutral|"
    "MusicPlayer_eu4_na_signs_of_victory|music/signs_of_victory.ogg|dlc108_north_america_music|war|"
    "MusicPlayer_eu4_sea_discoveries_revealed|music/discoveries_revealed.ogg|dlc109_south_east_asia_music|discovery|indian"
    "MusicPlayer_eu4_sea_undisclosed_tactics|music/undisclosed_tactics.ogg|dlc109_south_east_asia_music|war|indian"
    "MusicPlayer_eu4_sea_undiscovered_territory|music/undiscovered_territory.ogg|dlc109_south_east_asia_music|discovery|"
    "MusicPlayer_eu4_waf_new_destiny_awaits|music/a_new_destiny_awaits.ogg|dlc112_west_african_music_pack|neutral|african"
    "MusicPlayer_eu4_waf_into_the_wild|music/into_the_wild.ogg|dlc112_west_african_music_pack|neutral|african"
    "MusicPlayer_eu4_waf_strategy_reborn|music/strategy_reborn.ogg|dlc112_west_african_music_pack|war|"
    "MusicPlayer_eu4_eaf_encounters_in_the_sun|music/encounters_in_the_sun_ea.ogg|dlc113_east_african_music_pack|neutral|african"
    "MusicPlayer_eu4_eaf_neverending_dunes|music/neverending_dunes.ogg|dlc113_east_african_music_pack|neutral|african"
    "MusicPlayer_eu4_eaf_the_long_walk|music/the_long_walk_ea.ogg|dlc113_east_african_music_pack|peace|"
    "MusicPlayer_eu4_gds3_aarle|music/aarle.ogg|dlc114_guns_drums_and_steel_volume_3|neutral|"
    "MusicPlayer_eu4_gds3_after_the_rain|music/after_the_rain.ogg|dlc114_guns_drums_and_steel_volume_3|peace|"
    "MusicPlayer_eu4_gds3_darkness_falls|music/darkness_falls.ogg|dlc114_guns_drums_and_steel_volume_3|war|"
    "MusicPlayer_eu4_gds3_demons|music/demons.ogg|dlc114_guns_drums_and_steel_volume_3|war|"
    "MusicPlayer_eu4_gds3_kettil|music/kettil.ogg|dlc114_guns_drums_and_steel_volume_3|neutral|"
    "MusicPlayer_eu4_gds3_last_stand|music/last_stand.ogg|dlc114_guns_drums_and_steel_volume_3|war|"
    "MusicPlayer_eu4_gds3_legends_north|music/legends_of_the_north.ogg|dlc114_guns_drums_and_steel_volume_3|neutral|european"
    "MusicPlayer_eu4_gds3_over_seas|music/over_seas.ogg|dlc114_guns_drums_and_steel_volume_3|discovery|"
    "MusicPlayer_eu4_gds3_ravens|music/ravens.ogg|dlc114_guns_drums_and_steel_volume_3|war|"
    "MusicPlayer_eu4_gds3_the_conqueror|music/the_conqueror.ogg|dlc114_guns_drums_and_steel_volume_3|war|"
    "MusicPlayer_eu4_gds3_voices|music/voices.ogg|dlc114_guns_drums_and_steel_volume_3|neutral|"
    "MusicPlayer_eu4_gds3_whispering_forest|music/whispering_forest.ogg|dlc114_guns_drums_and_steel_volume_3|peace|"
    "MusicPlayer_eu4_scan_battle_of_scandinavia|music/battle_of_scandinavia.ogg|dlc117_scandinavian_music_pack|war|european"
    "MusicPlayer_eu4_scan_lands_of_midnight_sun|music/lands_of_midnight_sun.ogg|dlc117_scandinavian_music_pack|peace|european"
    "MusicPlayer_eu4_scan_united_we_stand|music/united_we_stand.ogg|dlc117_scandinavian_music_pack|neutral|european"
    "MusicPlayer_eu4_balt_crowned_in_tallin|music/crowned_in_tallin.ogg|dlc118_baltics_music_pack|neutral|european"
    "MusicPlayer_eu4_balt_knights_of_swords|music/knights_of_swords.ogg|dlc118_baltics_music_pack|war|european"
    "MusicPlayer_eu4_balt_rise_of_the_balts|music/rise_of_the_balts.ogg|dlc118_baltics_music_pack|neutral|european"
    "MusicPlayer_eu4_ott_conquest_of_constantinople|music/conquest_of_constantinople.ogg|dlc121_ottoman_music_pack|war|middle_east"
    "MusicPlayer_eu4_ott_redrawing_the_map|music/redrawing_the_map.ogg|dlc121_ottoman_music_pack|neutral|middle_east"
    "MusicPlayer_eu4_ott_suleiman_the_magnificent|music/suleiman_the_magnificent.ogg|dlc121_ottoman_music_pack|neutral|middle_east"
    "MusicPlayer_eu4_chi_path_of_the_dragon|music/path_of_the_dragon.ogg|dlc122_chinese_music_pack|neutral|east_asian"
    "MusicPlayer_eu4_chi_ports_of_china|music/ports_of_china.ogg|dlc122_chinese_music_pack|peace|east_asian"
    "MusicPlayer_eu4_chi_staff_of_the_emperor|music/staff_of_the_emperor.ogg|dlc122_chinese_music_pack|neutral|east_asian"
    "MusicPlayer_eu4_fr_a_new_king_arrives|music/a_new_king_arrives.ogg|dlc123_french_music_pack|neutral|european"
    "MusicPlayer_eu4_fr_castle_of_versailles|music/castle_of_versailles.ogg|dlc123_french_music_pack|peace|european"
    "MusicPlayer_eu4_fr_le_premier_jour|music/le_premier_jour.ogg|dlc123_french_music_pack|neutral|european"
    "MusicPlayer_eu4_ann_brief_history|music/a_brief_history_of_everything.ogg|dlc127_10th_anniversary|neutral|"
    "MusicPlayer_eu4_ann_world_to_explore|music/a_world_to_explore.ogg|dlc127_10th_anniversary|discovery|"
    "MusicPlayer_eu4_ann_all_roads_rome|music/all_roads_lead_to_rome.ogg|dlc127_10th_anniversary|neutral|european"
    "MusicPlayer_eu4_ann_back_motherland|music/back_to_the_motherland.ogg|dlc127_10th_anniversary|neutral|"
    "MusicPlayer_eu4_ann_clara_umbra|music/clara_umbra.ogg|dlc127_10th_anniversary|neutral|"
    "MusicPlayer_eu4_ann_dawn_empire|music/dawn_of_an_empire.ogg|dlc127_10th_anniversary|neutral|"
    "MusicPlayer_eu4_ann_in_taverns|music/in_taverns_and_great_halls.ogg|dlc127_10th_anniversary|peace|"
    "MusicPlayer_eu4_ann_into_beyond|music/into_the_beyond.ogg|dlc127_10th_anniversary|discovery|"
    "MusicPlayer_eu4_ann_one_world|music/one_world.ogg|dlc127_10th_anniversary|neutral|"
    "MusicPlayer_eu4_ann_conquistador|music/the_conquistador.ogg|dlc127_10th_anniversary|war|european"
    "MusicPlayer_eu4_egy_blue_nile|music/blue_nile.ogg|dlc130_egyptian_music_pack|neutral|middle_east"
    "MusicPlayer_eu4_egy_fates_of_the_desert|music/fates_of_the_desert.ogg|dlc130_egyptian_music_pack|neutral|middle_east"
    "MusicPlayer_eu4_egy_pharaohs_new_era|music/pharaohs_of_a_new_era.ogg|dlc130_egyptian_music_pack|neutral|middle_east"
    "MusicPlayer_eu4_egy_ruler_pyramids|music/ruler_of_the_pyramids.ogg|dlc130_egyptian_music_pack|neutral|middle_east"
    "MusicPlayer_eu4_per_battles_on_persian_borders|music/battles_on_persian_borders.ogg|dlc131_persian_music_pack|war|middle_east"
    "MusicPlayer_eu4_per_harbors_of_the_caspian_sea|music/harbors_of_the_caspian_sea.ogg|dlc131_persian_music_pack|neutral|middle_east"
    "MusicPlayer_eu4_per_mount_damavand|music/mount_damavand.ogg|dlc131_persian_music_pack|neutral|middle_east"
    "MusicPlayer_eu4_per_nader_shah|music/nader_shah.ogg|dlc131_persian_music_pack|neutral|middle_east"
    "MusicPlayer_eu4_cau_battle_of_kakheti|music/battle_of_kakheti.ogg|dlc132_caucasian_music_pack|war|european"
    "MusicPlayer_eu4_cau_caucasus_mountains|music/caucasus_mountains.ogg|dlc132_caucasian_music_pack|neutral|european"
    "MusicPlayer_eu4_cau_days_of_glory|music/days_of_glory.ogg|dlc132_caucasian_music_pack|neutral|european"
    "MusicPlayer_eu4_cau_sight_black_sea|music/sight_of_the_black_sea.ogg|dlc132_caucasian_music_pack|neutral|european"
    "MusicPlayer_eu4_hre_continuation_diplomacy|music/a_continuation_of_diplomacy.ogg|dlc133_utopia_hre_music_pack|peace|european"
    "MusicPlayer_eu4_hre_autumn_aachen|music/autumn_in_aachen.ogg|dlc133_utopia_hre_music_pack|peace|european"
    "MusicPlayer_eu4_hre_charlemagne_legacy|music/charlemange_s_legacy.ogg|dlc133_utopia_hre_music_pack|neutral|european"
    "MusicPlayer_eu4_hre_election_habsburg|music/election_of_a_habsburg.ogg|dlc133_utopia_hre_music_pack|neutral|european"
    "MusicPlayer_eu4_hre_imperial_diet|music/imperial_diet.ogg|dlc133_utopia_hre_music_pack|neutral|european"
    "MusicPlayer_eu4_hre_life_shadow_kingdom|music/life_under_the_shadow_kingdom.ogg|dlc133_utopia_hre_music_pack|neutral|"
    "MusicPlayer_eu4_hre_ninety_five_theses|music/ninety_five_theses.ogg|dlc133_utopia_hre_music_pack|neutral|european"
    "MusicPlayer_eu4_hre_rise_loyal_subjects|music/now_rise_my_loyal_subjects.ogg|dlc133_utopia_hre_music_pack|war|european"
    "MusicPlayer_eu4_hre_order_diplomacy|music/order_and_diplomacy.ogg|dlc133_utopia_hre_music_pack|peace|european"
    "MusicPlayer_eu4_hre_prussian_ambitions|music/prussian_ambitions.ogg|dlc133_utopia_hre_music_pack|war|european"
    "MusicPlayer_eu4_ksp3_blood_old_gods|music/blood_of_the_old_gods.ogg|dlc134_kairis_soundtrack_part_3|war|"
    "MusicPlayer_eu4_ksp3_city_worlds_desire|music/city_of_the_world_s_desire.ogg|dlc134_kairis_soundtrack_part_3|neutral|middle_east"
    "MusicPlayer_eu4_ksp3_crossing_seas|music/crossing_the_seas.ogg|dlc134_kairis_soundtrack_part_3|discovery|"
    "MusicPlayer_eu4_ksp3_eastern_mists|music/eastern_mists.ogg|dlc134_kairis_soundtrack_part_3|neutral|east_asian"
    "MusicPlayer_eu4_ksp3_fine_day_sacrifice|music/fine_day_for_sacrifice.ogg|dlc134_kairis_soundtrack_part_3|war|south_american"
    "MusicPlayer_eu4_ksp3_gaelic_summers|music/gaelic_summers.ogg|dlc134_kairis_soundtrack_part_3|peace|european"
    "MusicPlayer_eu4_ksp3_hundred_years_war|music/hundred_years_war.ogg|dlc134_kairis_soundtrack_part_3|war|european"
    "MusicPlayer_eu4_ksp3_la_bataille_iberia|music/la_bataille_de_iberia.ogg|dlc134_kairis_soundtrack_part_3|war|european"
    "MusicPlayer_eu4_ksp3_march_empire|music/march_for_the_empire.ogg|dlc134_kairis_soundtrack_part_3|war|"
    "MusicPlayer_eu4_ksp3_old_families|music/old_families.ogg|dlc134_kairis_soundtrack_part_3|neutral|"
    "MusicPlayer_eu4_ksp3_prelude_march|music/prelude_s_march.ogg|dlc134_kairis_soundtrack_part_3|neutral|"
    "MusicPlayer_eu4_ksp3_shogunate_fall|music/the_shogunate_will_fall.ogg|dlc134_kairis_soundtrack_part_3|war|east_asian"
    "MusicPlayer_eu4_ksp3_siege_of_vienna|music/the_siege_of_vienna.ogg|dlc134_kairis_soundtrack_part_3|war|european"
    "MusicPlayer_eu4_natam_aztec_theme|music/aztec_theme.ogg|dlc138_native_america_music_pack|neutral|south_american"
    "MusicPlayer_eu4_natam_inca_theme|music/inca_theme.ogg|dlc138_native_america_music_pack|neutral|south_american"
    "MusicPlayer_eu4_natam_mayan_theme|music/mayan_theme.ogg|dlc138_native_america_music_pack|neutral|south_american"
    "MusicPlayer_eu4_cas_hordes_centralasian|music/hordes_centralasian.ogg|dlc139_central_asia_music_pack|war|middle_east"
    "MusicPlayer_eu4_cas_mughal_indian_persian|music/mughal_indian_persian.ogg|dlc139_central_asia_music_pack|neutral|indian"
    "MusicPlayer_eu4_cas_oman_arabic|music/oman_arabic.ogg|dlc139_central_asia_music_pack|neutral|middle_east"
    "MusicPlayer_eu4_ce_austria_theme|music/austria_theme.ogg|dlc140_central_europe_music_pack|neutral|european"
    "MusicPlayer_eu4_ce_hungary_theme|music/hungary_theme.ogg|dlc140_central_europe_music_pack|neutral|european"
    "MusicPlayer_eu4_ce_netherlands_theme|music/netherlands_theme.ogg|dlc140_central_europe_music_pack|neutral|european"
)

# --- FUNCTIONS ---------------------------------------------

function Write-Status($msg) { Write-Host "[EU4 Soundtrack] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)     { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg)   { Write-Host "[!]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)    { Write-Host "[X]  $msg" -ForegroundColor Red }

function Get-WemId([string]$EventName) {
    [uint64]$h = 2166136261
    [uint64]$mask = 4294967295
    [uint64]$mul  = 16777619
    foreach ($c in ($EventName + "_wem").ToLower().ToCharArray()) {
        $h = ($h * $mul) -band $mask
        $h = $h -bxor [uint64][byte][char]$c
    }
    return [uint32]$h
}

function Find-SteamLibraries {
    # Get Steam root from registry
    $steamRoot = $null
    try { $steamRoot = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -EA Stop).SteamPath -replace '/','\\' } catch {}
    if (-not $steamRoot) {
        try { $steamRoot = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -EA Stop).InstallPath } catch {}
    }
    $libs = @()
    if ($steamRoot -and (Test-Path $steamRoot)) {
        $libs += $steamRoot
        $vdf = "$steamRoot\steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            Get-Content $vdf | Select-String '"path"' | ForEach-Object {
                if ($_ -match '"path"\s+"([^"]+)"') {
                    $libs += $Matches[1] -replace '\\\\','\'
                }
            }
        }
    }
    return $libs
}

function Find-EU4Path {
    foreach ($lib in (Find-SteamLibraries)) {
        $p = "$lib\steamapps\common\Europa Universalis IV"
        if (Test-Path "$p\eu4.exe") { return $p }
    }
    # EU4 registry fallback
    try {
        $reg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 236850" -EA Stop
        if (Test-Path "$($reg.InstallLocation)\eu4.exe") { return $reg.InstallLocation }
    } catch {}
    return $null
}


function Find-Ogg([string]$SourceOgg, [string]$DlcDir, [string]$Eu4Path) {
    if (-not $DlcDir) {
        # Base game
        $p = "$Eu4Path\music\$SourceOgg"
        if (Test-Path $p) { return $p }
    } else {
        # DLC zip
        $dlcPath = "$Eu4Path\dlc\$DlcDir"
        if (-not (Test-Path $dlcPath)) { return $null }
        $zips = Get-ChildItem "$dlcPath\*.zip" -EA SilentlyContinue
        foreach ($zip in $zips) {
            $tmpExtract = "$env:TEMP\eu4snd_extract"
            try {
                Add-Type -Assembly System.IO.Compression.FileSystem -EA SilentlyContinue
                $zf = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
                $entry = $zf.Entries | Where-Object { $_.FullName -like "*$SourceOgg" } | Select-Object -First 1
                if ($entry) {
                    $outPath = "$tmpExtract\$($entry.Name)"
                    New-Item -ItemType Directory -Force $tmpExtract | Out-Null
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $outPath, $true)
                    $zf.Dispose()
                    return $outPath
                }
                $zf.Dispose()
            } catch {}
        }
    }
    return $null
}


function Find-EU5MusicBank {
    $rel = "steamapps\common\Europa Universalis V\game\loading_screen\sound\banks\windows\sb_music_logic.bnk"
    # Workshop mod lives in <library>\steamapps\workshop\content\3450310\<id> - EU5 is usually in that library
    $libs = @((Resolve-Path "$ModDir\..\..\..\..\.." -EA SilentlyContinue).Path) + (Find-SteamLibraries)
    foreach ($lib in $libs) {
        if ($lib -and (Test-Path "$lib\$rel")) { return "$lib\$rel" }
    }
    return $null
}

function Sync-FromGitHub {
    # Banks come from Steam Workshop, not GitHub
}

# --- MAIN --------------------------------------------------

Write-Host ""
Write-Host "  EU4 Soundtrack for EU5" -ForegroundColor White
Write-Host "  ---------------------" -ForegroundColor DarkGray
Write-Host ""

# 1. Check & convert missing tracks
New-Item -ItemType Directory -Force $MediaDir | Out-Null

$missing = @()
foreach ($track in $Tracks) {
    if ($null -eq $track -or $track -notmatch "\|") { continue }
    $eventName = ($track -split "\|")[0]
    # Truncated WEMs (interrupted conversion in older versions) are converted again
    if (-not [BankBuilder]::IsValidWem("$MediaDir\$(Get-WemId $eventName).wem")) { $missing += $track }
}

if ($missing.Count -eq 0) {
    Write-Ok "All $($Tracks.Count) tracks ready!"
} else {
    Write-Status "Locating EU4..."
    $eu4Path = Find-EU4Path
    if (-not $eu4Path) {
        Write-Err "EU4 not found. Make sure Europa Universalis IV is installed on this Steam account."
        Write-Host ""; Read-Host "Press Enter to close"; exit 1
    } else {
        Write-Ok "EU4: $eu4Path"

        # Build work list (only tracks with OGG found: base game + installed DLCs)
        $workList = @()
        foreach ($track in $missing) {
            $parts = $track -split "\|"
            $eventName = $parts[0]; $srcOgg = $parts[1]
            $dlcDir = if ($parts.Count -gt 2 -and $parts[2] -ne "") { $parts[2] } else { $null }
            $wemPath = "$MediaDir\$(Get-WemId $eventName).wem"
            $oggPath = Find-Ogg $srcOgg $dlcDir $eu4Path
            if ($oggPath) {
                $workList += [PSCustomObject]@{
                    EventName=$eventName; OggPath=$oggPath; WemPath=$wemPath
                }
            }
        }
        $skipped = $missing.Count - $workList.Count

        if ($workList.Count -eq 0) {
            Write-Ok "$($Tracks.Count - $missing.Count) tracks ready, $skipped need DLCs that are not installed"
        } else {
            # Tools are only needed when there is something to convert
            Write-Status "Checking tools..."
            $pcbValid = (Test-Path $PcbPath) -and ((Get-Item $PcbPath).Length -eq 74387)
            if (-not $pcbValid) {
                Write-Status "Downloading packed_codebooks.bin..."
                New-Item -ItemType Directory -Force (Split-Path $PcbPath) | Out-Null
                Invoke-WebRequest "https://github.com/hcs64/ww2ogg/raw/master/packed_codebooks_aoTuV_603.bin" `
                    -OutFile $PcbPath -UseBasicParsing
            }
            if (-not (Test-Path $PcbPath)) {
                Write-Err "packed_codebooks.bin download failed"
                Read-Host "Press Enter to close"; exit 1
            }

            if (-not (Test-Path $OggEncPath)) {
                Write-Status "Downloading oggenc2 (aoTuV)..."
                $zip = "$env:TEMP\eu4wem_cache\oggenc2.zip"
                Invoke-WebRequest "https://www.rarewares.org/files/ogg/oggenc2.88-1.3.7-aoTuVb6.03-x64.zip" `
                    -OutFile $zip -UseBasicParsing
                $tmp2 = "$env:TEMP\eu4wem_cache\oggenc2_tmp"
                [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp2)
                $exe = Get-ChildItem $tmp2 -Recurse -Filter "oggenc2*.exe" | Select-Object -First 1
                if ($exe) { Copy-Item $exe.FullName $OggEncPath }
                Remove-Item $tmp2 -Recurse -Force -EA SilentlyContinue; Remove-Item $zip -EA SilentlyContinue
            }
            if (-not (Test-Path $FlacDll)) {
                Write-Status "Downloading libFLAC.dll..."
                $zip = "$env:TEMP\eu4wem_cache\flac_dll.zip"
                Invoke-WebRequest "https://www.rarewares.org/files/lossless/flac_dll-1.5.0-x64.zip" `
                    -OutFile $zip -UseBasicParsing
                $tmp2 = "$env:TEMP\eu4wem_cache\flac_tmp"
                [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp2)
                $dll = Get-ChildItem $tmp2 -Recurse -Filter "libFLAC.dll" | Select-Object -First 1
                if ($dll) { Copy-Item $dll.FullName $FlacDll }
                Remove-Item $tmp2 -Recurse -Force -EA SilentlyContinue; Remove-Item $zip -EA SilentlyContinue
            }
            if (-not (Test-Path $OggEncPath) -or -not (Test-Path $FlacDll)) {
                Write-Err "oggenc2 / libFLAC.dll download failed"
                Read-Host "Press Enter to close"; exit 1
            }
            Write-Ok "Conversion tools ready"

            $ffmpeg = Get-Command ffmpeg -EA SilentlyContinue
            if (-not $ffmpeg) {
                $ffpaths = @(
                    "$env:ProgramFiles\ffmpeg\bin\ffmpeg.exe",
                    "$env:ProgramFiles\ffmpeg\ffmpeg.exe",
                    'C:\ffmpeg\bin\ffmpeg.exe',
                    'C:\ffmpeg\ffmpeg.exe'
                )
                foreach ($p in $ffpaths) { if (Test-Path $p) { $ffmpeg = Get-Item $p; break } }
                if (-not $ffmpeg) {
                    $wg = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
                    if (Test-Path $wg) { $ffmpeg = Get-ChildItem "$wg\Gyan.FFmpeg*\**\ffmpeg.exe" -Recurse -EA SilentlyContinue | Select-Object -First 1 }
                }
            }
            if (-not $ffmpeg) {
                Write-Err "FFmpeg not found. Install it: winget install ffmpeg  -- then restart Steam."
                Write-Host ""; Read-Host "Press Enter to close"; exit 1
            }
            Write-Ok "FFmpeg found"
            $ffmpegExe = if ($ffmpeg.Path) { $ffmpeg.Path } else { $ffmpeg.FullName }

            # Parallel conversion (N jobs = half of CPU cores, min 2, max 8)
            $maxJobs = [Math]::Max(2, [Math]::Min(8, [Environment]::ProcessorCount / 2))
            Write-Status "Converting $($workList.Count) track(s) ($maxJobs parallel jobs)..."

            # Parallel runner: ffmpeg WAV + oggenc2(aoTuV) OGG + C# WEM
            $convertScript = {
                param($OggPath, $WemPath, $TmpDir, $CacheDll, $PcbPath, $OggEncPath, $FfmpegExe)
                try {
                    Add-Type -Path $CacheDll -EA Stop
                    $stem = [System.IO.Path]::GetFileNameWithoutExtension($WemPath)
                    $ogg  = "$TmpDir\$stem.ogg"
                    New-Item -ItemType Directory -Force $TmpDir | Out-Null
                    # OGG -> aoTuV OGG via pipe (no temp WAV file)
                    $r = cmd /c "`"$FfmpegExe`" -y -i `"$OggPath`" -ar 48000 -ac 2 -f wav pipe:1 2>nul | `"$OggEncPath`" -q 6 -o `"$ogg`" - 2>nul"
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ogg)) {
                        # Fallback: use temp WAV if pipe failed
                        $wav = "$TmpDir\$stem.wav"
                        $r = & $FfmpegExe -y -i $OggPath -ar 48000 -ac 2 -acodec pcm_s16le $wav 2>&1
                        if ($LASTEXITCODE -ne 0) { return "ffmpeg failed: $($r | Select-Object -Last 3 | Out-String)" }
                        $r = & $OggEncPath -q 6 -o $ogg $wav 2>&1
                        if ($LASTEXITCODE -ne 0) { return "oggenc2 failed: $($r | Select-Object -Last 3 | Out-String)" }
                        Remove-Item $wav -EA SilentlyContinue
                    }
                    # Step 3: OGG -> WEM (external packed codebooks)
                    $res = [OggToWem]::Convert($ogg, $WemPath, $PcbPath)
                    Remove-Item $ogg -EA SilentlyContinue
                    if ($res -ne "ok") { return "WEM failed: $res" }
                    return $true
                } catch { return "Error: $_" }
            }

            $jobs = @(); $done = 0; $failed = 0; $idx = 0
            while ($idx -lt $workList.Count -or $jobs.Count -gt 0) {
                while ($jobs.Count -lt $maxJobs -and $idx -lt $workList.Count) {
                    $item = $workList[$idx++]
                    Write-Host "  [+] $($item.EventName)" -ForegroundColor DarkCyan
                    $job = Start-Job -ScriptBlock $convertScript `
                        -ArgumentList $item.OggPath,$item.WemPath,$TmpDir,$CacheDll,$PcbPath,$OggEncPath,$ffmpegExe
                    $jobs += [PSCustomObject]@{Job=$job; Name=$item.EventName}
                }
                # Check completed jobs
                $remaining = @()
                foreach ($j in $jobs) {
                    if ($j.Job.State -in 'Completed','Failed','Stopped') {
                        $result = Receive-Job $j.Job -EA SilentlyContinue
                        Remove-Job $j.Job -Force
                        if ($result -eq $true) { $done++ } else {
                            $failed++
                            Write-Warn "Failed: $($j.Name)"
                            if ($result -and $result -ne $false) { Write-Host "  -> $result" -ForegroundColor DarkYellow }
                        }
                    } else { $remaining += $j }
                }
                $jobs = $remaining
                if ($jobs.Count -ge $maxJobs -or ($idx -ge $workList.Count -and $jobs.Count -gt 0)) {
                    Start-Sleep -Milliseconds 500
                }
            }
            Write-Ok "Done: $done  Failed: $failed  Skipped (no DLC): $skipped"
        }
        Remove-Item "$env:TEMP\eu4snd_extract" -Recurse -Force -EA SilentlyContinue
    }
}

# 2. Sync sound banks with the WEM files actually present. Runs every launch: Steam
#    restores the shipped banks on mod updates, and EU5 patches change its music bank.
Write-Status "Updating sound banks..."
$wemIds = foreach ($track in $Tracks) { Get-WemId (($track -split "\|")[0]) }
$res = [BankBuilder]::BuildMedia([uint32[]]$wemIds, $MediaDir, "$BanksDir\eu4_soundtrack_media.bnk")
if ($res -notlike "ok *") {
    Write-Err "media.bnk build failed: $res"
    Write-Host ""; Read-Host "Press Enter to close"; exit 1
}
$r = $res -split " "
Write-Ok "media.bnk: $($r[1]) tracks ($($r[2]))"

$eu5Bank = Find-EU5MusicBank
if (-not $eu5Bank) {
    Write-Err "EU5 not found (sb_music_logic.bnk). Make sure Europa Universalis V is installed on this Steam account."
    Write-Host ""; Read-Host "Press Enter to close"; exit 1
}
$bankTracks = foreach ($track in $Tracks) { $p = $track -split "\|"; "$($p[0])|$($p[3])|$($p[4])" }
$res = [BankBuilder]::BuildMusic($eu5Bank, [string[]]$bankTracks, $MediaDir, "$BanksDir\eu4_soundtrack_music.bnk")
if ($res -notlike "ok *") {
    Write-Err "music.bnk build failed: $res"
    Write-Host ""; Read-Host "Press Enter to close"; exit 1
}
$r = $res -split " "
Write-Ok "music.bnk: $($r[1]) tracks in playlists, $($r[2]) not installed left out ($($r[3]))"

# Done - game launched by launch.cmd via %*
Write-Host ""
Write-Status "Setup complete. Game starting..."
Start-Sleep -Seconds 2
