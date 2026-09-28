// Win32 definitions for recycle bin query + batch move-to-recycle-bin (SHFileOperation).
// Shared by recycle-stats.ps1 and clean-batch.ps1 via Add-Type.
using System;
using System.Runtime.InteropServices;

public class RecycleBinApi
{
    [StructLayout(LayoutKind.Sequential)]
    public struct SHQUERYRBINFO { public int cbSize; public long i64Size; public long i64NumItems; }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SHQueryRecycleBin(string pszRootPath, ref SHQUERYRBINFO q);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SHFILEOPSTRUCT
    {
        public IntPtr hwnd; public uint wFunc; public string pFrom; public string pTo;
        public ushort fFlags; public int fAnyOperationsAborted; public IntPtr hNameMappings; public string lpszProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SHFileOperation(ref SHFILEOPSTRUCT lpFileOp);

    public static string Query(string root)
    {
        var q = new SHQUERYRBINFO(); q.cbSize = Marshal.SizeOf(q);
        SHQueryRecycleBin(root, ref q);
        return string.Format("{0} GB, {1} items", Math.Round(q.i64Size / 1073741824.0, 2), q.i64NumItems);
    }

    // paths are joined with NUL and double-NUL terminated.
    public static int SendToRecycleBin(string[] paths)
    {
        var op = new SHFILEOPSTRUCT();
        op.wFunc = 3; // FO_DELETE
        op.pFrom = string.Join("\0", paths) + "\0\0";
        op.fFlags = 0x0040 | 0x0010 | 0x0400 | 0x0200; // ALLOWUNDO | NOCONFIRMATION | NOERRORUI | SILENT
        op.fAnyOperationsAborted = 0; op.hNameMappings = IntPtr.Zero; op.lpszProgressTitle = "";
        return SHFileOperation(ref op);
    }
}
