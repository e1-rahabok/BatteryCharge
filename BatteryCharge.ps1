<#
.SYNOPSIS
  Switch the Dell battery charge mode without rebooting, using Dell Command | Configure (cctk.exe).

.PARAMETER Mode
  Window - Small window showing the current setting, with a button to switch it
  Full   - Standard charging, charges to 100% (use before going unplugged)
  Limit  - Custom charging, stops at -Stop (default 65%) and resumes below -Start (default 50%)
  Toggle - Switch between Full and Limit
  Status - Show the current setting only

.NOTES
  Needs admin rights; the script re-launches itself elevated (UAC prompt) when needed.
  Dell limits: Start 50-95, Stop 55-100, Stop must be at least 5 above Start.
#>
param(
    [ValidateSet('Window', 'Full', 'Limit', 'Toggle', 'Status')]
    [string]$Mode = 'Toggle',
    [ValidateRange(50, 95)]  [int]$Start = 50,
    [ValidateRange(55, 100)] [int]$Stop = 65,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$cctk = 'C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
function Show-Result([string]$Text, [string]$Icon = 'Information') {
    if (-not $Quiet) {
        [void][System.Windows.Forms.MessageBox]::Show($Text, 'Battery Charge', 'OK', $Icon)
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

if (-not (Test-Path $cctk)) {
    Show-Result "Dell Command | Configure not found at:`n$cctk" 'Error'; exit 1
}
if ($Stop - $Start -lt 5) {
    Show-Result "Stop ($Stop) must be at least 5 higher than Start ($Start)." 'Error'; exit 1
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

# Throws with cctk's output when the change fails.
function Set-ChargeMode([string]$Target) {
    $value = if ($Target -eq 'Full') { 'Standard' } else { "Custom:$Start-$Stop" }
    $output = & $cctk "--PrimaryBattChargeCfg=$value" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set charge mode (cctk exit $LASTEXITCODE).`n`n$($output.Trim())"
    }
}

function Show-Window {
    Add-Type -AssemblyName PresentationFramework
    $dark = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue).AppsUseLightTheme -eq 0
    $c = if ($dark) {
        @{ Bg = '#202020'; Text = '#FFFFFF'; Sub = '#C8C8C8'; Line = '#3A3A3A'; Shell = '#9E9E9E'
           Ok = '#6CCB5F'; Warn = '#FFB900'; Accent = '#4CC2FF'; OnAccent = '#000000' }
    } else {
        @{ Bg = '#F3F3F3'; Text = '#1A1A1A'; Sub = '#5D5D5D'; Line = '#DEDEDE'; Shell = '#7A7A7A'
           Ok = '#0F7B0F'; Warn = '#9D5D00'; Accent = '#005FB8'; OnAccent = '#FFFFFF' }
    }
    # Battery gauge: 90 px outline, 2.5 px border and 4 px padding leave 77 px for the fill.
    $gauge = 77
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Battery Charge" SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen" Topmost="True" UseLayoutRounding="True"
        Background="@Bg@" Foreground="@Text@" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="14">
  <Window.Icon>
    <DrawingImage>
      <DrawingImage.Drawing>
        <DrawingGroup>
          <GeometryDrawing Brush="Transparent" Geometry="M0,0 H32 V32 H0 Z"/>
          <GeometryDrawing Geometry="M3,9.5 H25 A2,2 0 0 1 27,11.5 V20.5 A2,2 0 0 1 25,22.5 H3 A2,2 0 0 1 1,20.5 V11.5 A2,2 0 0 1 3,9.5 Z">
            <GeometryDrawing.Pen><Pen Brush="@Text@" Thickness="2"/></GeometryDrawing.Pen>
          </GeometryDrawing>
          <GeometryDrawing Brush="@Text@" Geometry="M28.5,13 H30 V19 H28.5 Z"/>
          <GeometryDrawing Brush="@Accent@" Geometry="M4,12.5 H17 V19.5 H4 Z"/>
        </DrawingGroup>
      </DrawingImage.Drawing>
    </DrawingImage>
  </Window.Icon>
  <StackPanel Width="300" Margin="28,24,28,24">
    <StackPanel Orientation="Horizontal">
      <Grid Width="96" Height="46" VerticalAlignment="Center">
        <Border Width="90" HorizontalAlignment="Left" CornerRadius="8" BorderThickness="2.5" BorderBrush="@Shell@" Padding="4">
          <Grid>
            <Border x:Name="Fill" HorizontalAlignment="Left" CornerRadius="4"/>
            <Rectangle x:Name="CapMark" Width="2" HorizontalAlignment="Left" Fill="@Text@" Opacity="0.6" RadiusX="1" RadiusY="1"/>
          </Grid>
        </Border>
        <Border Width="5" Height="16" HorizontalAlignment="Right" Margin="0,0,1,0" CornerRadius="0,3,3,0" Background="@Shell@"/>
      </Grid>
      <StackPanel Margin="18,0,0,0" VerticalAlignment="Center">
        <TextBlock x:Name="Percent" FontFamily="Segoe UI Variable Display, Segoe UI" FontSize="32" FontWeight="SemiBold"/>
        <TextBlock x:Name="Power" Foreground="@Sub@" FontSize="13"/>
      </StackPanel>
    </StackPanel>
    <Border Height="1" Background="@Line@" Margin="0,20,0,18"/>
    <StackPanel Orientation="Horizontal">
      <Ellipse x:Name="Dot" Width="9" Height="9" VerticalAlignment="Center" Margin="0,2,9,0"/>
      <TextBlock x:Name="Status" FontSize="17" FontWeight="SemiBold"/>
    </StackPanel>
    <TextBlock x:Name="Detail" Foreground="@Sub@" FontSize="13" TextWrapping="Wrap" Margin="18,3,0,20"/>
    <Button x:Name="Action" Height="38" Background="@Accent@" Foreground="@OnAccent@" FontWeight="SemiBold"
            Cursor="Hand" IsDefault="True" FocusVisualStyle="{x:Null}">
      <Button.Template>
        <ControlTemplate TargetType="Button">
          <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.9"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.78"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.5"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Button.Template>
    </Button>
    <TextBlock x:Name="Hint" Foreground="@Sub@" FontSize="12" HorizontalAlignment="Center" Margin="0,8,0,0"/>
  </StackPanel>
</Window>
"@
    foreach ($k in $c.Keys) { $xaml = $xaml.Replace("@$k@", $c[$k]) }
    $window = [Windows.Markup.XamlReader]::Parse($xaml)
    $ui = @{}
    foreach ($n in 'Fill', 'CapMark', 'Percent', 'Power', 'Dot', 'Status', 'Detail', 'Action', 'Hint') { $ui[$n] = $window.FindName($n) }
    $brush = { param($hex) (New-Object Windows.Media.BrushConverter).ConvertFromString($hex) }

    # Handlers run in a child scope, so shared state lives in a hashtable.
    $state = @{ Capped = $false }
    $showBattery = {
        $b = Get-Battery
        if ($b) {
            $ui.Percent.Text = "$($b.Percent)%"
            $ui.Power.Text = $b.State.Substring(0, 1).ToUpper() + $b.State.Substring(1)
            $ui.Fill.Width = [Math]::Max(6, $gauge * $b.Percent / 100)
        } else {
            $ui.Percent.Text = '--'; $ui.Power.Text = 'No battery found'; $ui.Fill.Width = 0
        }
    }
    $refresh = {
        $cfg = Get-ChargeCfg
        $state.Capped = $cfg -match '^Custom:(\d+)-(\d+)$'
        if ($state.Capped) {
            $resume, $cap = $Matches[1], $Matches[2]
            $ui.Status.Text = "Capped at $cap%"
            $ui.Detail.Text = "Charging stops at $cap% and resumes below $resume%."
            $ui.Action.Content = 'Charge to 100%'
            $ui.Hint.Text = 'Do this before you go unplugged.'
            $ui.CapMark.Margin = New-Object Windows.Thickness(($gauge * $cap / 100 - 1), 0, 0, 0)
            $ui.CapMark.Visibility = 'Visible'
            $color = $c.Ok
        } else {
            $ui.Status.Text = 'Charging to 100%'
            $ui.Detail.Text = if ($cfg -eq 'Standard') { 'No charge limit is set.' } else { "BIOS charge mode: $cfg" }
            $ui.Action.Content = "Cap at $Stop%"
            $ui.Hint.Text = 'Protects the battery while you stay plugged in.'
            $ui.CapMark.Visibility = 'Collapsed'
            $color = $c.Warn
        }
        $ui.Dot.Fill = & $brush $color
        $ui.Fill.Background = & $brush $color
        & $showBattery
    }
    $ui.Action.add_Click({
        $ui.Action.IsEnabled = $false
        $ui.Action.Content = 'Applying...'
        # Let the button repaint before cctk blocks the UI thread.
        $window.Dispatcher.Invoke([action] {}, [Windows.Threading.DispatcherPriority]::Background)
        try {
            Set-ChargeMode $(if ($state.Capped) { 'Full' } else { 'Limit' })
        } catch {
            [void][Windows.MessageBox]::Show($window, $_.Exception.Message, 'Battery Charge', 'OK', 'Error')
        }
        & $refresh
        $ui.Action.IsEnabled = $true
    })

    $timer = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromSeconds(30) }
    $timer.add_Tick($showBattery)
    $timer.Start()

    if ($dark) {
        Add-Type -Namespace Win32 -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);'
        $window.add_SourceInitialized({
            $hwnd = (New-Object Windows.Interop.WindowInteropHelper($window)).Handle
            $on = 1; [void][Win32.Dwm]::DwmSetWindowAttribute($hwnd, 20, [ref]$on, 4)   # dark title bar
        })
    }
    # A task-started window can open behind others; Topmost is dropped once it's shown.
    $window.add_ContentRendered({ $window.Activate(); $window.Topmost = $false })

    & $refresh
    [void]$window.ShowDialog()
}

if ($Mode -eq 'Window') { Show-Window; exit 0 }

$current = Get-ChargeCfg
if ($Mode -eq 'Status') {
    Show-Result "Charge mode: $current`n$(Get-BatteryText)"; exit 0
}
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
