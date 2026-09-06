function Get-CopilotAtelierReparseTag
{
    [CmdletBinding()]
    [OutputType([System.UInt32])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $LiteralPath
    )

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT)
    {
        throw 'Native reparse tags are only available on Windows.'
    }

    if (-not ('CopilotAtelier.NativeReparsePoint' -as [type]))
    {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace CopilotAtelier
{
    public static class NativeReparsePoint
    {
        private const uint OpenExisting = 3;
        private const uint ShareReadWriteDelete = 7;
        private const uint OpenReparsePoint = 0x00200000;
        private const uint BackupSemantics = 0x02000000;
        private const int FileAttributeTagInfoClass = 9;

        [StructLayout(LayoutKind.Sequential)]
        private struct FileAttributeTagInfo
        {
            public uint FileAttributes;
            public uint ReparseTag;
        }

        [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(
            string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
            uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetFileInformationByHandleEx(
            SafeFileHandle fileHandle, int informationClass,
            out FileAttributeTagInfo information, uint bufferSize);

        public static uint ReadTag(string path)
        {
            using (SafeFileHandle handle = CreateFile(path, 0, ShareReadWriteDelete, IntPtr.Zero,
                OpenExisting, OpenReparsePoint | BackupSemantics, IntPtr.Zero))
            {
                if (handle.IsInvalid)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }

                FileAttributeTagInfo information;
                if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfoClass,
                    out information, (uint)Marshal.SizeOf(typeof(FileAttributeTagInfo))))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }

                return information.ReparseTag;
            }
        }
    }
}
'@ -ErrorAction Stop
    }

    $nativePath = [System.IO.Path]::GetFullPath($LiteralPath)
    if (-not $nativePath.StartsWith('\\?\', [System.StringComparison]::Ordinal))
    {
        $nativePath = if ($nativePath.StartsWith('\\', [System.StringComparison]::Ordinal))
        {
            '\\?\UNC\' + $nativePath.Substring(2)
        }
        else
        {
            '\\?\' + $nativePath
        }
    }
    [CopilotAtelier.NativeReparsePoint]::ReadTag($nativePath)
}