Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class LayeredWindowHelper
{
    [StructLayout(LayoutKind.Sequential)]
    struct POINT { public int x; public int y; }
    [StructLayout(LayoutKind.Sequential)]
    struct SIZE { public int cx; public int cy; }
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct BLENDFUNCTION
    {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct BITMAPINFOHEADER
    {
        public int biSize;
        public int biWidth;
        public int biHeight;
        public short biPlanes;
        public short biBitCount;
        public int biCompression;
        public int biSizeImage;
        public int biXPelsPerMeter;
        public int biYPelsPerMeter;
        public int biClrUsed;
        public int biClrImportant;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct BITMAPINFO
    {
        public BITMAPINFOHEADER bmiHeader;
        public int bmiColors;
    }

    const int ULW_ALPHA = 0x02;
    const byte AC_SRC_OVER = 0x00;
    const byte AC_SRC_ALPHA = 0x01;
    const int GWL_EXSTYLE = -20;
    const int WS_EX_LAYERED = 0x80000;

    [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
    static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll", ExactSpelling = true)]
    static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
    static extern IntPtr CreateCompatibleDC(IntPtr hDC);
    [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
    static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
    static extern IntPtr SelectObject(IntPtr hdc, IntPtr hObj);
    [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
    static extern bool DeleteObject(IntPtr hObj);
    [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
    static extern IntPtr CreateDIBSection(IntPtr hdc, ref BITMAPINFO pbmi, uint iUsage, out IntPtr ppvBits, IntPtr hSection, uint dwOffset);
    [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
    static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);
    [DllImport("user32.dll", SetLastError = true)]
    static extern int GetWindowLong(IntPtr hwnd, int nIndex);
    [DllImport("user32.dll", SetLastError = true)]
    static extern int SetWindowLong(IntPtr hwnd, int nIndex, int dwNewLong);

    public static void EnableLayered(Form form)
    {
        int exStyle = GetWindowLong(form.Handle, GWL_EXSTYLE);
        SetWindowLong(form.Handle, GWL_EXSTYLE, exStyle | WS_EX_LAYERED);
    }

    public static void SetBitmap(Form form, Bitmap bitmap, int targetWidth, int targetHeight)
    {
        using (Bitmap resized = new Bitmap(targetWidth, targetHeight, PixelFormat.Format32bppArgb))
        {
            using (Graphics rg = Graphics.FromImage(resized))
            {
                rg.CompositingMode = CompositingMode.SourceCopy;
                rg.InterpolationMode = InterpolationMode.HighQualityBicubic;
                rg.PixelOffsetMode = PixelOffsetMode.HighQuality;
                rg.DrawImage(bitmap, new Rectangle(0, 0, targetWidth, targetHeight));
            }
            SetBitmapCore(form, resized);
        }
    }

    static void SetBitmapCore(Form form, Bitmap bitmap)
    {
        Rectangle rect = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
        using (Bitmap srcArgb = bitmap.Clone(rect, PixelFormat.Format32bppArgb))
        {
            BitmapData srcData = srcArgb.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            int stride = srcData.Stride;
            int height = srcData.Height;
            byte[] buffer = new byte[stride * height];
            Marshal.Copy(srcData.Scan0, buffer, 0, buffer.Length);
            srcArgb.UnlockBits(srcData);

            for (int i = 0; i < buffer.Length; i += 4)
            {
                byte b = buffer[i];
                byte g = buffer[i + 1];
                byte r = buffer[i + 2];
                byte a = buffer[i + 3];
                buffer[i] = (byte)(b * a / 255);
                buffer[i + 1] = (byte)(g * a / 255);
                buffer[i + 2] = (byte)(r * a / 255);
            }

            IntPtr screenDc = GetDC(IntPtr.Zero);
            IntPtr memDc = CreateCompatibleDC(screenDc);
            IntPtr hBitmap = IntPtr.Zero;
            IntPtr oldBitmap = IntPtr.Zero;
            try
            {
                BITMAPINFO bmi = new BITMAPINFO();
                bmi.bmiHeader.biSize = Marshal.SizeOf(typeof(BITMAPINFOHEADER));
                bmi.bmiHeader.biWidth = bitmap.Width;
                bmi.bmiHeader.biHeight = -bitmap.Height;
                bmi.bmiHeader.biPlanes = 1;
                bmi.bmiHeader.biBitCount = 32;
                bmi.bmiHeader.biCompression = 0;

                IntPtr bits;
                hBitmap = CreateDIBSection(memDc, ref bmi, 0, out bits, IntPtr.Zero, 0);
                Marshal.Copy(buffer, 0, bits, buffer.Length);

                oldBitmap = SelectObject(memDc, hBitmap);

                SIZE size = new SIZE { cx = bitmap.Width, cy = bitmap.Height };
                POINT pointSource = new POINT { x = 0, y = 0 };
                POINT topPos = new POINT { x = form.Left, y = form.Top };
                BLENDFUNCTION blend = new BLENDFUNCTION
                {
                    BlendOp = AC_SRC_OVER,
                    BlendFlags = 0,
                    SourceConstantAlpha = 255,
                    AlphaFormat = AC_SRC_ALPHA
                };

                UpdateLayeredWindow(form.Handle, screenDc, ref topPos, ref size, memDc, ref pointSource, 0, ref blend, ULW_ALPHA);
            }
            finally
            {
                ReleaseDC(IntPtr.Zero, screenDc);
                if (oldBitmap != IntPtr.Zero) SelectObject(memDc, oldBitmap);
                if (hBitmap != IntPtr.Zero) DeleteObject(hBitmap);
                DeleteDC(memDc);
            }
        }
    }
}
'@

$fukuroDir = Join-Path $HOME 'fukuro-chan'
$stateFile = Join-Path $fukuroDir 'state.txt'

$imagePaths = @{
    idle    = Join-Path $fukuroDir 'idle.png'
    running = Join-Path $fukuroDir 'running.png'
    waiting = Join-Path $fukuroDir 'waiting.png'
}

foreach ($entry in $imagePaths.GetEnumerator()) {
    if (-not (Test-Path $entry.Value)) {
        [System.Windows.Forms.MessageBox]::Show(
            "fukuro-chan の表情画像が見つかりません:`n$($entry.Value)`n`n$fukuroDir に idle.png / running.png / waiting.png (背景透過PNG) を用意してから起動してください。",
            "fukuro-chan",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        exit 1
    }
}

function Import-PngImage {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $stream = New-Object System.IO.MemoryStream(,$bytes)
    return New-Object System.Drawing.Bitmap($stream)
}

$images = @{
    idle    = Import-PngImage $imagePaths.idle
    running = Import-PngImage $imagePaths.running
    waiting = Import-PngImage $imagePaths.waiting
}

$targetHeight = 220
$scale = $targetHeight / $images.idle.Height
$targetWidth = [int]([Math]::Round($images.idle.Width * $scale))

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Size = New-Object System.Drawing.Size($targetWidth, $targetHeight)

$primaryScreen = [System.Windows.Forms.Screen]::AllScreens | Where-Object { $_.Primary } | Select-Object -First 1
if (-not $primaryScreen) { $primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen }
$workArea = $primaryScreen.WorkingArea

$petLeft = $workArea.Right - $targetWidth - 20
$petTop = $workArea.Bottom - $targetHeight - 20
if ($petLeft -lt $workArea.Left) { $petLeft = $workArea.Left + 20 }
if ($petTop -lt $workArea.Top) { $petTop = $workArea.Top + 20 }

$form.Location = New-Object System.Drawing.Point($petLeft, $petTop)

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$exitItem = $contextMenu.Items.Add('終了')
$form.ContextMenuStrip = $contextMenu
$exitItem.add_Click({
    $form.Close()
})

$script:dragging = $false
$script:dragOffset = New-Object System.Drawing.Point(0, 0)

$form.Add_MouseDown({
    $script:dragging = $true
    $script:dragOffset = $_.Location
})
$form.Add_MouseMove({
    if ($script:dragging) {
        $screenPoint = $form.PointToScreen($_.Location)
        $form.Location = New-Object System.Drawing.Point(($screenPoint.X - $script:dragOffset.X), ($screenPoint.Y - $script:dragOffset.Y))
    }
})
$form.Add_MouseUp({
    $script:dragging = $false
})

$script:lastState = ''

function Update-PetImage {
    param([string]$State)
    [LayeredWindowHelper]::SetBitmap($form, $images[$State], $targetWidth, $targetHeight)
    $script:lastState = $State
}

$form.Add_Shown({
    try {
        [LayeredWindowHelper]::EnableLayered($form)
        Update-PetImage 'idle'
    } catch {
        $_ | Out-String | Set-Content -Path (Join-Path $fukuroDir 'pet-error.log') -Encoding UTF8
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.add_Tick({
    $state = 'idle'
    try {
        if (Test-Path $stateFile) {
            $raw = (Get-Content -Path $stateFile -Raw -ErrorAction Stop).Trim()
            if ($raw -eq 'idle' -or $raw -eq 'running' -or $raw -eq 'waiting') {
                $state = $raw
            }
        }
    } catch {
        $state = $script:lastState
    }

    if ($state -ne $script:lastState -and $state -ne '') {
        try {
            Update-PetImage $state
        } catch {
            $_ | Out-String | Add-Content -Path (Join-Path $fukuroDir 'pet-error.log') -Encoding UTF8
        }
    }
})
$timer.Start()

[System.Windows.Forms.Application]::Run($form)
