<#
.SYNOPSIS
  Power Manager: battery charge limit, battery health and Hibernate now in one small Windows 11 window.

.PARAMETER Mode
  Window - The Power Manager window (charge limit, battery health, Hibernate now)
  Full   - Standard charging, charges to 100% (use before going unplugged)       [Dell only]
  Limit  - Custom charging, stops at -Stop (default 65%), resumes below -Start   [Dell only]
  Toggle - Switch between Full and Limit                                         [Dell only]
  Status - Show the charge setting and battery health

.NOTES
  Needs admin rights; the script re-launches itself elevated (UAC prompt) when needed.
  The charge limit uses Dell Command | Configure (cctk.exe). Without it, the window still shows
  battery health and Hibernate now, and hides the charge limit card.
  Dell limits: Start 50-95, Stop 55-100, Stop must be at least 5 above Start.
  Customise: colours in $Theme below; put background.png or background.jpg next to this script
  to replace the built-in background. See README.md.
#>
param(
    [ValidateSet('Window', 'Full', 'Limit', 'Toggle', 'Status')]
    [string]$Mode = 'Toggle',
    [ValidateRange(50, 95)]  [int]$Start = 50,
    [ValidateRange(55, 100)] [int]$Stop = 65,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# Window colours ("Bloom Glass", dark). Change these to re-theme the window.
$Theme = @{
    Bg1 = '#040A22'; Bg2 = '#0A1C55'; Bg3 = '#0B2C86'          # background gradient, top-left to bottom-right
    Ribbon1 = '#1A4DFF'; Ribbon2 = '#3F8CFF'; Ribbon3 = '#5BA3FF'; RibbonLine = '#9CC4FF'   # flowing ribbons
    Ring1 = '#7CE3FF'; Ring2 = '#3D7BFF'                       # battery ring gauge
    Accent1 = '#2F6BFF'; Accent2 = '#5AB0FF'; Glow = '#3D7BFF' # main button gradient and glow
    Text = '#FFFFFF'; Sub = '#C3D2FA'; Icon = '#7FB2FF'
    Ok = '#8EE07F'; Warn = '#FFC84A'; Bad = '#FF99A4'          # health / status colours
}

# Dell Command | Configure installs to either Program Files folder depending on version.
$cctk = "${env:ProgramFiles(x86)}\Dell\Command Configure\X86_64\cctk.exe",
        "$env:ProgramFiles\Dell\Command Configure\X86_64\cctk.exe" |
    Where-Object { Test-Path $_ } | Select-Object -First 1

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
function Show-Result([string]$Text, [string]$Icon = 'Information') {
    if (-not $Quiet) {
        [void][System.Windows.Forms.MessageBox]::Show($Text, 'Power Manager', 'OK', $Icon)
    }
    Write-Output $Text
}

# Re-launch elevated if needed.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', "`"$PSCommandPath`"", '-Mode', $Mode, '-Start', $Start, '-Stop', $Stop)
    if ($Quiet) { $argList += '-Quiet' }
    try {
        Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList -WindowStyle Hidden
    } catch {
        Show-Result "Admin rights are required and the UAC prompt was cancelled." 'Warning'
    }
    exit
}

if (-not $cctk -and $Mode -in 'Full', 'Limit', 'Toggle') {
    Show-Result "Dell Command | Configure (cctk.exe) was not found, so the charge limit can't be changed." 'Error'; exit 1
}
if ($Stop - $Start -lt 5) {
    Show-Result "Stop ($Stop) must be at least 5 higher than Start ($Start)." 'Error'; exit 1
}

# Native calls, compiled once: battery driver query and title bar colour.
if (-not ('PowerManager.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace PowerManager {
public static class Native {
    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved; }
    [StructLayout(LayoutKind.Sequential)]
    struct BATTERY_QUERY_INFORMATION { public uint BatteryTag; public int InformationLevel; public int AtRate; }
    [StructLayout(LayoutKind.Sequential)]
    struct BATTERY_INFORMATION {
        public uint Capabilities; public byte Technology; public byte R1, R2, R3;
        public byte C1, C2, C3, C4;
        public uint DesignedCapacity, FullChargedCapacity, DefaultAlert1, DefaultAlert2, CriticalBias, CycleCount;
    }
    [DllImport("setupapi.dll", SetLastError = true)]
    static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr h, int flags);
    [DllImport("setupapi.dll", SetLastError = true)]
    static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr info, ref Guid g, int i, ref SP_DEVICE_INTERFACE_DATA d);
    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr set, ref SP_DEVICE_INTERFACE_DATA d, IntPtr detail, int size, out int req, IntPtr info);
    [DllImport("setupapi.dll")]
    static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr t);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(SafeFileHandle h, uint code, ref uint inBuf, int inSize, out uint outBuf, int outSize, out int ret, IntPtr o);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(SafeFileHandle h, uint code, ref BATTERY_QUERY_INFORMATION inBuf, int inSize, out BATTERY_INFORMATION outBuf, int outSize, out int ret, IntPtr o);

    const uint IOCTL_BATTERY_QUERY_TAG = 0x294040, IOCTL_BATTERY_QUERY_INFORMATION = 0x294044;

    // Asks each battery driver directly (the source powercfg /batteryreport reads), no admin needed.
    // One entry per battery: { DesignedCapacity mWh, FullChargedCapacity mWh, CycleCount }.
    public static List<uint[]> QueryBatteries() {
        var result = new List<uint[]>();
        Guid battery = new Guid("72631e54-78a4-11d0-bcf7-00aa00b7b32a");   // GUID_DEVCLASS_BATTERY
        IntPtr set = SetupDiGetClassDevs(ref battery, IntPtr.Zero, IntPtr.Zero, 0x12);   // PRESENT | DEVICEINTERFACE
        if (set == new IntPtr(-1)) return result;
        try {
            for (int i = 0; i < 8; i++) {
                var d = new SP_DEVICE_INTERFACE_DATA(); d.cbSize = Marshal.SizeOf(d);
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref battery, i, ref d)) break;
                int size;
                SetupDiGetDeviceInterfaceDetail(set, ref d, IntPtr.Zero, 0, out size, IntPtr.Zero);
                IntPtr detail = Marshal.AllocHGlobal(size);
                string path;
                try {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);   // SP_DEVICE_INTERFACE_DETAIL_DATA_W.cbSize
                    if (!SetupDiGetDeviceInterfaceDetail(set, ref d, detail, size, out size, IntPtr.Zero)) continue;
                    path = Marshal.PtrToStringUni(new IntPtr(detail.ToInt64() + 4));
                } finally { Marshal.FreeHGlobal(detail); }
                using (var h = CreateFile(path, 0xC0000000, 3, IntPtr.Zero, 3, 0x80, IntPtr.Zero)) {
                    if (h.IsInvalid) continue;
                    uint wait = 0, tag; int ret;
                    if (!DeviceIoControl(h, IOCTL_BATTERY_QUERY_TAG, ref wait, 4, out tag, 4, out ret, IntPtr.Zero) || tag == 0) continue;
                    var q = new BATTERY_QUERY_INFORMATION(); q.BatteryTag = tag; q.InformationLevel = 0;   // BatteryInformation
                    BATTERY_INFORMATION bi;
                    if (!DeviceIoControl(h, IOCTL_BATTERY_QUERY_INFORMATION, ref q, Marshal.SizeOf(q), out bi,
                            Marshal.SizeOf(typeof(BATTERY_INFORMATION)), out ret, IntPtr.Zero)) continue;
                    result.Add(new uint[] { bi.DesignedCapacity, bi.FullChargedCapacity, bi.CycleCount });
                }
            }
        } finally { SetupDiDestroyDeviceInfoList(set); }
        return result;
    }

    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
}
}
'@
}

function Get-ChargeCfg {
    $line = & $cctk --PrimaryBattChargeCfg 2>&1 | Select-String 'PrimaryBattChargeCfg=' | Select-Object -First 1
    if ($line) { ($line.ToString() -split '=', 2)[1].Trim() } else { 'Unknown' }
}

function Get-Battery {
    $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $b) { return $null }
    $state = switch ($b.BatteryStatus) { 1 { 'on battery' } 2 { 'on AC' } 6 { 'charging' } 3 { 'fully charged' } default { "status $($b.BatteryStatus)" } }
    [pscustomobject]@{ Percent = [int]$b.EstimatedChargeRemaining; State = $state }
}

function Get-BatteryText {
    $b = Get-Battery
    if ($b) { "Battery now: $($b.Percent)% ($($b.State))" } else { '' }
}

# Design capacity, current full charge capacity (both mWh) and cycle count, summed over all
# batteries. Cycles is $null when the battery doesn't report it.
function Get-BatteryHealth {
    $all = @([PowerManager.Native]::QueryBatteries() | Where-Object { $_[0] -gt 0 })
    if (-not $all) { return $null }
    $design = ($all | ForEach-Object { [double]$_[0] } | Measure-Object -Sum).Sum
    $full = ($all | ForEach-Object { [double]$_[1] } | Measure-Object -Sum).Sum
    $cycles = ($all | ForEach-Object { [double]$_[2] } | Measure-Object -Sum).Sum
    [pscustomobject]@{
        DesignWh = $design / 1000
        FullWh   = $full / 1000
        Health   = [Math]::Min(100, [Math]::Round(100 * $full / $design))
        Cycles   = if ($cycles -gt 0) { [int]$cycles } else { $null }
    }
}

function Get-HealthText {
    $h = Get-BatteryHealth
    if (-not $h) { return 'Battery health: not reported' }
    $cyc = if ($null -ne $h.Cycles) { $h.Cycles } else { 'not reported' }
    'Original capacity: {0:N1} Wh{4}Full charge capacity: {1:N1} Wh ({2}% health){4}Charge cycles: {3}' -f
        $h.DesignWh, $h.FullWh, $h.Health, $cyc, "`n"
}

# Throws with cctk's output when the change fails.
function Set-ChargeMode([string]$Target) {
    $value = if ($Target -eq 'Full') { 'Standard' } else { "Custom:$Start-$Stop" }
    $output = & $cctk "--PrimaryBattChargeCfg=$value" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set charge mode (cctk exit $LASTEXITCODE).`n`n$($output.Trim())"
    }
}

# Saves everything to disk and powers off. Unlike sleep (Modern Standby), no app or driver can keep
# the laptop running and warm, and nothing is closed: the session is restored on power-on.
function Invoke-Hibernate {
    $output = & "$env:SystemRoot\System32\shutdown.exe" /h 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Windows couldn't hibernate (shutdown /h exit $LASTEXITCODE).`n`n$($output.Trim())`n`n" +
            "Hibernate may be turned off. To turn it on, run this in an admin PowerShell: powercfg /hibernate on"
    }
}

function New-WindowXaml {
    # Card inner width: 400 window - 40 margin - 36 card padding - 2 border = 322 px.
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Power Manager" Width="400" SizeToContent="Height" ResizeMode="CanMinimize" WindowStyle="None"
        WindowStartupLocation="CenterScreen" Topmost="True" UseLayoutRounding="True" Background="@Bg1@"
        Foreground="@Text@" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="14">
  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="44" GlassFrameThickness="0,0,0,1" ResizeBorderThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>
  <Window.Icon>
    <DrawingImage>
      <DrawingImage.Drawing>
        <DrawingGroup>
          <GeometryDrawing Brush="Transparent" Geometry="M0,0 H32 V32 H0 Z"/>
          <GeometryDrawing Geometry="M3,9.5 H25 A2,2 0 0 1 27,11.5 V20.5 A2,2 0 0 1 25,22.5 H3 A2,2 0 0 1 1,20.5 V11.5 A2,2 0 0 1 3,9.5 Z">
            <GeometryDrawing.Pen><Pen Brush="@Text@" Thickness="2"/></GeometryDrawing.Pen>
          </GeometryDrawing>
          <GeometryDrawing Brush="@Text@" Geometry="M28.5,13 H30 V19 H28.5 Z"/>
          <GeometryDrawing Brush="@Ring2@" Geometry="M4,12.5 H17 V19.5 H4 Z"/>
        </DrawingGroup>
      </DrawingImage.Drawing>
    </DrawingImage>
  </Window.Icon>
  <Window.Resources>
    <Style x:Key="Glass" TargetType="Border">
      <Setter Property="CornerRadius" Value="16"/>
      <Setter Property="Padding" Value="18,14,18,16"/>
      <Setter Property="Margin" Value="0,0,0,12"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Background">
        <Setter.Value>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#30FFFFFF" Offset="0"/>
            <GradientStop Color="#10FFFFFF" Offset="1"/>
          </LinearGradientBrush>
        </Setter.Value>
      </Setter>
      <Setter Property="BorderBrush">
        <Setter.Value>
          <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#60FFFFFF" Offset="0"/>
            <GradientStop Color="#14FFFFFF" Offset="1"/>
          </LinearGradientBrush>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Tile" TargetType="Border">
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Background" Value="#16FFFFFF"/>
      <Setter Property="Padding" Value="11,9"/>
    </Style>
    <Style x:Key="Label" TargetType="TextBlock">
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="@Sub@"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="Small" TargetType="TextBlock">
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Foreground" Value="@Sub@"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
    <Style x:Key="Icon" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Foreground" Value="@Icon@"/>
      <Setter Property="Margin" Value="0,1,9,0"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <ControlTemplate x:Key="Pill" TargetType="Button">
      <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
              BorderThickness="{TemplateBinding BorderThickness}"
              CornerRadius="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
      </Border>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.88"/></Trigger>
        <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.72"/></Trigger>
        <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.5"/></Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Template" Value="{StaticResource Pill}"/>
      <Setter Property="Tag" Value="20"/>
      <Setter Property="Height" Value="40"/>
      <Setter Property="Foreground" Value="@Text@"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Background">
        <Setter.Value>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="@Accent1@" Offset="0"/>
            <GradientStop Color="@Accent2@" Offset="1"/>
          </LinearGradientBrush>
        </Setter.Value>
      </Setter>
      <Setter Property="Effect">
        <Setter.Value><DropShadowEffect Color="@Glow@" BlurRadius="24" ShadowDepth="0" Opacity="0.8"/></Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Outline" TargetType="Button" BasedOn="{StaticResource Primary}">
      <Setter Property="Tag" Value="18"/>
      <Setter Property="Height" Value="36"/>
      <Setter Property="Padding" Value="16,0"/>
      <Setter Property="Background" Value="#16FFFFFF"/>
      <Setter Property="BorderBrush" Value="#88A9C8FF"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Effect" Value="{x:Null}"/>
    </Style>
    <Style x:Key="TitleButton" TargetType="Button">
      <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Foreground" Value="#D6E2FF"/>
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#22FFFFFF"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="#14FFFFFF"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid ClipToBounds="True">
    <!-- Bloom background: gradient with blurred, flowing ribbons. -->
    <Grid.Background>
      <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="@Bg1@" Offset="0"/>
        <GradientStop Color="@Bg2@" Offset="0.55"/>
        <GradientStop Color="@Bg3@" Offset="1"/>
      </LinearGradientBrush>
    </Grid.Background>
    <Canvas IsHitTestVisible="False">
      <Path Data="M520,40 C330,90 250,250 330,420 C400,560 300,700 120,820 L520,820 Z" Opacity="0.85">
        <Path.Fill><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="@Ribbon1@" Offset="0"/><GradientStop Color="@Bg2@" Offset="1"/></LinearGradientBrush></Path.Fill>
        <Path.Effect><BlurEffect Radius="40"/></Path.Effect>
      </Path>
      <Path Data="M470,-20 C260,120 210,300 300,430 C370,540 250,660 60,800" StrokeThickness="70" Opacity="0.75">
        <Path.Stroke><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="@Ribbon2@" Offset="0"/><GradientStop Color="@Ribbon1@" Offset="0.6"/><GradientStop Color="@Bg2@" Offset="1"/></LinearGradientBrush></Path.Stroke>
        <Path.Effect><BlurEffect Radius="18"/></Path.Effect>
      </Path>
      <Path Data="M450,-10 C250,130 205,300 292,428 C360,530 245,650 50,790" StrokeThickness="3" Opacity="0.5" Stroke="@RibbonLine@">
        <Path.Effect><BlurEffect Radius="2"/></Path.Effect>
      </Path>
      <Path Data="M500,120 C360,210 330,330 390,450 C440,560 380,650 260,800" StrokeThickness="40" Opacity="0.55">
        <Path.Stroke><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="@Ribbon3@" Offset="0"/><GradientStop Color="@Ribbon1@" Offset="1"/></LinearGradientBrush></Path.Stroke>
        <Path.Effect><BlurEffect Radius="12"/></Path.Effect>
      </Path>
      <Ellipse Canvas.Left="-120" Canvas.Top="-140" Width="360" Height="360" Opacity="0.35">
        <Ellipse.Fill><RadialGradientBrush><GradientStop Color="@Ribbon2@" Offset="0"/><GradientStop Color="Transparent" Offset="1"/></RadialGradientBrush></Ellipse.Fill>
      </Ellipse>
    </Canvas>
    <Image x:Name="BgImage" Stretch="UniformToFill" Opacity="0.35" Visibility="Collapsed" IsHitTestVisible="False"/>

    <DockPanel Margin="20,0,12,8">
      <!-- Title bar (drag area comes from WindowChrome) -->
      <Grid DockPanel.Dock="Top" Height="44">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Style="{StaticResource Icon}" Text="&#xE945;" Foreground="@RibbonLine@"/>
          <TextBlock Text="Power Manager" FontSize="12.5" Foreground="#D6E2FF"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <Button x:Name="MinButton" Style="{StaticResource TitleButton}" Content="&#xE921;" ToolTip="Minimize"/>
          <Button x:Name="CloseButton" Style="{StaticResource TitleButton}" Content="&#xE8BB;" ToolTip="Close"/>
        </StackPanel>
      </Grid>

      <StackPanel Margin="0,0,8,0">
        <!-- Ring gauge -->
        <Grid Width="200" Height="200" Margin="0,4,0,14">
          <Ellipse Width="170" Height="170" Opacity="0.5">
            <Ellipse.Fill><RadialGradientBrush><GradientStop Color="@Accent1@" Offset="0"/><GradientStop Color="Transparent" Offset="1"/></RadialGradientBrush></Ellipse.Fill>
          </Ellipse>
          <Canvas Width="180" Height="180">
            <Ellipse Width="156" Height="156" Canvas.Left="12" Canvas.Top="12" Stroke="#22FFFFFF" StrokeThickness="12"/>
            <Path x:Name="Arc" StrokeThickness="12" StrokeStartLineCap="Round" StrokeEndLineCap="Round">
              <Path.Stroke><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="@Ring1@" Offset="0"/><GradientStop Color="@Ring2@" Offset="1"/></LinearGradientBrush></Path.Stroke>
              <Path.Effect><DropShadowEffect Color="@Ring2@" BlurRadius="22" ShadowDepth="0" Opacity="0.9"/></Path.Effect>
            </Path>
            <Line x:Name="CapTick" Stroke="@Text@" StrokeThickness="2.5" Opacity="0.85" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
          </Canvas>
          <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
            <TextBlock x:Name="Percent" FontFamily="Segoe UI Variable Display, Segoe UI" FontSize="46" FontWeight="SemiBold" HorizontalAlignment="Center"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
              <TextBlock x:Name="PowerIcon" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Foreground="@RibbonLine@" Margin="0,2,6,0"/>
              <TextBlock x:Name="Power" FontSize="13" Foreground="@Sub@"/>
            </StackPanel>
          </StackPanel>
        </Grid>

        <!-- Charge limit (Dell Command | Configure) -->
        <Border Style="{StaticResource Glass}">
          <StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
              <TextBlock Style="{StaticResource Icon}" Text="&#xEBB5;"/>
              <TextBlock Style="{StaticResource Label}" Text="Charge limit"/>
            </StackPanel>
            <Grid>
              <StackPanel Margin="0,0,90,0">
                <TextBlock x:Name="Status" FontSize="18" FontWeight="SemiBold"/>
                <TextBlock x:Name="Detail" Style="{StaticResource Small}" FontSize="12.5" Margin="0,2,0,0"/>
              </StackPanel>
              <Border x:Name="Badge" HorizontalAlignment="Right" VerticalAlignment="Center" CornerRadius="10" Padding="9,3">
                <TextBlock x:Name="BadgeText" FontSize="11.5" FontWeight="SemiBold"/>
              </Border>
            </Grid>
            <Button x:Name="Action" Style="{StaticResource Primary}" Margin="0,14,0,0" IsDefault="True">
              <StackPanel Orientation="Horizontal">
                <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Text="&#xE945;" FontSize="13" Margin="0,2,8,0"/>
                <TextBlock x:Name="ActionText"/>
              </StackPanel>
            </Button>
          </StackPanel>
        </Border>

        <!-- Battery health -->
        <Border Style="{StaticResource Glass}">
          <StackPanel>
            <Grid Margin="0,0,0,10">
              <StackPanel Orientation="Horizontal">
                <TextBlock Style="{StaticResource Icon}" Text="&#xE95E;"/>
                <TextBlock Style="{StaticResource Label}" Text="Battery health"/>
              </StackPanel>
              <TextBlock x:Name="HealthText" HorizontalAlignment="Right" VerticalAlignment="Center" FontSize="12.5" FontWeight="SemiBold"/>
            </Grid>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="8"/><ColumnDefinition/><ColumnDefinition Width="8"/><ColumnDefinition/></Grid.ColumnDefinitions>
              <Border Style="{StaticResource Tile}" ToolTip="Capacity the battery was designed to hold when new">
                <StackPanel><TextBlock x:Name="DesignCap" FontSize="19" FontWeight="SemiBold"/><TextBlock Style="{StaticResource Small}" FontSize="11.5" Text="Wh original"/></StackPanel>
              </Border>
              <Border Grid.Column="2" Style="{StaticResource Tile}" ToolTip="What a full charge holds today; drops as the battery wears">
                <StackPanel><TextBlock x:Name="FullCap" FontSize="19" FontWeight="SemiBold"/><TextBlock Style="{StaticResource Small}" FontSize="11.5" Text="Wh now"/></StackPanel>
              </Border>
              <Border Grid.Column="4" Style="{StaticResource Tile}" ToolTip="Full charge cycles completed so far">
                <StackPanel><TextBlock x:Name="Cycles" FontSize="19" FontWeight="SemiBold"/><TextBlock Style="{StaticResource Small}" FontSize="11.5" Text="cycles"/></StackPanel>
              </Border>
            </Grid>
            <Grid Height="6" Margin="0,12,0,0">
              <Border CornerRadius="3" Background="#22FFFFFF"/>
              <Border x:Name="HealthBar" CornerRadius="3" HorizontalAlignment="Left">
                <Border.Effect><DropShadowEffect x:Name="HealthGlow" BlurRadius="10" ShadowDepth="0" Opacity="0.8"/></Border.Effect>
              </Border>
            </Grid>
          </StackPanel>
        </Border>

        <!-- Hibernate -->
        <Border Style="{StaticResource Glass}">
          <Grid>
            <StackPanel VerticalAlignment="Center" Margin="0,0,140,0">
              <StackPanel Orientation="Horizontal">
                <TextBlock Style="{StaticResource Icon}" Text="&#xE708;"/>
                <TextBlock Style="{StaticResource Label}" Text="Turn off, keep everything"/>
              </StackPanel>
              <TextBlock Style="{StaticResource Small}" Text="Saves open apps, then powers off. No heat in your bag." Margin="0,4,0,0"/>
            </StackPanel>
            <Button x:Name="Hibernate" Style="{StaticResource Outline}" HorizontalAlignment="Right" VerticalAlignment="Center" Content="Hibernate now"/>
          </Grid>
        </Border>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@
    foreach ($k in $Theme.Keys) { $xaml = $xaml.Replace("@$k@", $Theme[$k]) }
    $xaml
}

function Show-Window {
    # PowerShell 7 doesn't load WPF's core assemblies along with PresentationFramework, so name all three.
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $c = $Theme
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $window = [Windows.Markup.XamlReader]::Parse((New-WindowXaml))
    $ui = @{}
    foreach ($n in 'Arc', 'CapTick', 'Percent', 'PowerIcon', 'Power', 'Status', 'Detail', 'Badge', 'BadgeText',
                   'Action', 'ActionText', 'HealthText', 'DesignCap', 'FullCap', 'Cycles', 'HealthBar', 'HealthGlow',
                   'Hibernate', 'MinButton', 'CloseButton', 'BgImage') {
        $ui[$n] = $window.FindName($n)
    }
    $brush = { param($hex) (New-Object Windows.Media.BrushConverter).ConvertFromString($hex) }
    $color = { param($hex) [Windows.Media.ColorConverter]::ConvertFromString($hex) }
    # Point on the gauge ring (centre 90,90) at a percentage of the full circle, clockwise from the top.
    $ringPoint = { param($pct, $r)
        $a = [Math]::Min(359.9, 3.6 * $pct) * [Math]::PI / 180
        New-Object Windows.Point((90 + $r * [Math]::Sin($a)), (90 - $r * [Math]::Cos($a)))
    }

    # Optional custom background: background.png / .jpg next to the script.
    $bgFile = Get-ChildItem $PSScriptRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -eq 'background' -and $_.Extension -in '.png', '.jpg', '.jpeg' } | Select-Object -First 1
    if ($bgFile) {
        $img = New-Object Windows.Media.Imaging.BitmapImage
        $img.BeginInit(); $img.CacheOption = 'OnLoad'; $img.UriSource = New-Object Uri($bgFile.FullName); $img.EndInit()
        $ui.BgImage.Source = $img
        $ui.BgImage.Visibility = 'Visible'
    }

    # Handlers run in a child scope, so shared state lives in a hashtable.
    $state = @{ Capped = $false; Hibernate = $false }
    $showBattery = {
        $b = Get-Battery
        if (-not $b) {
            $ui.Percent.Text = '--'; $ui.Power.Text = 'No battery found'; $ui.PowerIcon.Text = ''
            $ui.Arc.Visibility = 'Collapsed'
            return
        }
        $ui.Percent.Text = "$($b.Percent)%"
        $ui.Power.Text = if ($b.State -eq 'on battery') { 'On battery' } else { 'Plugged in' }
        $ui.PowerIcon.Text = if ($b.State -eq 'on battery') { [string][char]0xE83F } else { [string][char]0xE83E }
        if ($b.Percent -le 0) { $ui.Arc.Visibility = 'Collapsed'; return }
        $end = & $ringPoint $b.Percent 78
        $large = if ($b.Percent -gt 50) { 1 } else { 0 }
        $ui.Arc.Data = [Windows.Media.Geometry]::Parse(
            ('M90,12 A78,78 0 {0} 1 {1},{2}' -f $large, $end.X.ToString('0.##', $inv), $end.Y.ToString('0.##', $inv)))
        $ui.Arc.Visibility = 'Visible'
    }
    $showHealth = {
        $h = Get-BatteryHealth
        if (-not $h) {
            $ui.HealthText.Text = 'Not reported'; $ui.HealthText.Foreground = & $brush $c.Sub
            foreach ($n in 'DesignCap', 'FullCap', 'Cycles') { $ui[$n].Text = '--' }
            $ui.HealthBar.Width = 0
            return
        }
        $word, $hex = if ($h.Health -ge 80) { 'Good', $c.Ok } elseif ($h.Health -ge 60) { 'Worn', $c.Warn } else { 'Replace soon', $c.Bad }
        $ui.HealthText.Text = "$($h.Health)% $([char]0xB7) $word"
        $ui.HealthText.Foreground = & $brush $hex
        $ui.HealthBar.Background = & $brush $hex
        $ui.HealthGlow.Color = & $color $hex
        $ui.HealthBar.Width = [Math]::Max(6, 322 * $h.Health / 100)
        $ui.DesignCap.Text = '{0:N1}' -f $h.DesignWh
        $ui.FullCap.Text = '{0:N1}' -f $h.FullWh
        $ui.Cycles.Text = if ($null -ne $h.Cycles) { "$($h.Cycles)" } else { '--' }
    }
    $setBadge = { param($text, $hex)
        $ui.BadgeText.Text = $text
        $ui.BadgeText.Foreground = & $brush $hex
        $ui.Badge.Background = & $brush ('#2A' + $hex.TrimStart('#'))
    }
    $refresh = {
        $ui.CapTick.Visibility = 'Collapsed'
        if (-not $cctk) {
            $ui.Status.Text = 'Not available'
            $ui.Detail.Text = 'Needs Dell Command | Configure. See the README for other laptops.'
            $ui.Action.Visibility = 'Collapsed'; $ui.Badge.Visibility = 'Collapsed'
        } else {
            $cfg = Get-ChargeCfg
            $state.Capped = $cfg -match '^Custom:(\d+)-(\d+)$'
            if ($state.Capped) {
                $resume, $cap = $Matches[1], $Matches[2]
                $ui.Status.Text = "Capped at $cap%"
                $ui.Detail.Text = "Stops at $cap%, resumes below $resume%"
                $ui.ActionText.Text = 'Charge to 100%'
                & $setBadge 'Protected' $c.Ok
                # Tick across the ring where charging stops.
                $p1 = & $ringPoint ([int]$cap) 68; $p2 = & $ringPoint ([int]$cap) 90
                $ui.CapTick.X1 = $p1.X; $ui.CapTick.Y1 = $p1.Y; $ui.CapTick.X2 = $p2.X; $ui.CapTick.Y2 = $p2.Y
                $ui.CapTick.Visibility = 'Visible'
            } else {
                $ui.Status.Text = 'Charging to 100%'
                $ui.Detail.Text = if ($cfg -eq 'Standard') { 'No charge limit is set' } else { "BIOS charge mode: $cfg" }
                $ui.ActionText.Text = "Cap at $Stop%"
                & $setBadge 'Full charge' $c.Warn
            }
        }
        & $showBattery
        & $showHealth
    }
    $ui.Action.add_Click({
        $ui.Action.IsEnabled = $false
        $ui.ActionText.Text = 'Applying...'
        # Let the button repaint before cctk blocks the UI thread.
        $window.Dispatcher.Invoke([action] {}, [Windows.Threading.DispatcherPriority]::Background)
        try {
            Set-ChargeMode $(if ($state.Capped) { 'Full' } else { 'Limit' })
        } catch {
            [void][Windows.MessageBox]::Show($window, $_.Exception.Message, 'Power Manager', 'OK', 'Error')
        }
        & $refresh
        $ui.Action.IsEnabled = $true
    })
    $ui.Hibernate.add_Click({
        $ui.Hibernate.IsEnabled = $false
        $ui.Action.IsEnabled = $false
        $ui.Hibernate.Content = 'Hibernating...'
        # Hibernate after the window closes, so it isn't still open on power-on.
        $state.Hibernate = $true
        $window.Close()
    })
    $ui.MinButton.add_Click({ $window.WindowState = 'Minimized' })
    $ui.CloseButton.add_Click({ $window.Close() })
    $window.add_KeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $window.Close() } })

    $timer = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromSeconds(30) }
    $timer.add_Tick($showBattery)
    $timer.Start()

    $window.add_SourceInitialized({
        $hwnd = (New-Object Windows.Interop.WindowInteropHelper($window)).Handle
        # Dark frame and rounded corners on Windows 11; builds that don't know an attribute ignore it.
        $on = 1; [void][PowerManager.Native]::DwmSetWindowAttribute($hwnd, 20, [ref]$on, 4)      # immersive dark mode
        $round = 2; [void][PowerManager.Native]::DwmSetWindowAttribute($hwnd, 33, [ref]$round, 4) # rounded corners
    })
    # A task-started window can open behind others; Topmost is dropped once it's shown.
    $window.add_ContentRendered({ $window.Activate(); $window.Topmost = $false })

    & $refresh
    [void]$window.ShowDialog()
    if ($state.Hibernate) {
        try { Invoke-Hibernate } catch { Show-Result $_.Exception.Message 'Error' }
    }
}

if ($Mode -eq 'Window') { Show-Window; exit 0 }

if ($Mode -eq 'Status') {
    $charge = if ($cctk) { "Charge mode: $(Get-ChargeCfg)" } else { 'Charge mode: Dell Command | Configure not installed' }
    Show-Result "$charge`n$(Get-BatteryText)`n`n$(Get-HealthText)"; exit 0
}

$current = Get-ChargeCfg
if ($Mode -eq 'Toggle') {
    $Mode = if ($current -like 'Custom*') { 'Full' } else { 'Limit' }
}

try {
    Set-ChargeMode $Mode
} catch {
    Show-Result $_.Exception.Message 'Error'; exit 1
}
$new = Get-ChargeCfg

$msg = if ($Mode -eq 'Full') {
    "Charging to 100% enabled (Standard).`nSwitch back to the $Stop% limit when back on AC."
} else {
    "Charge limit set: stops at $Stop%, resumes below $Start%."
}
Show-Result "$msg`n`nBIOS setting: $new`n$(Get-BatteryText)"
