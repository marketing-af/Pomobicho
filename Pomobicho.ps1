param(
    [switch]$SelfTest,
    [string]$PreviewPath,
    [switch]$ShowSettings,
    [switch]$PreviewAlert,
    [string]$ResumeStatePath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PomobichoPopup {
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int index);
    [DllImport("user32.dll")] private static extern int SetWindowLong(IntPtr h, int index, int value);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }
    public static void Configure(IntPtr h) {
        SetWindowLong(h, -20, (GetWindowLong(h, -20) & ~0x00040000) | 0x00000080);
        SetWindowLong(h, -16, (GetWindowLong(h, -16) & ~0x00CF0000) | unchecked((int)0x80000000));
    }
    public static void PlaceAlert(IntPtr h, int x, int y, int width, int height) {
        if (!SetWindowPos(h, new IntPtr(-1), x, y, width, height, 0x0010))
            throw new InvalidOperationException("Could not position alert");
    }
    public static Rect WorkArea(IntPtr h) {
        var info = new MonitorInfo();
        info.Size = Marshal.SizeOf(info);
        if (!GetMonitorInfo(MonitorFromWindow(h, 2), ref info)) throw new InvalidOperationException("Monitor unavailable");
        return info.Work;
    }
}
'@

$script:settingsPath = Join-Path $PSScriptRoot 'preferencias.json'
$script:settings = @{
    FocusMinutes = 30
    BreakMinutes = 5
    Scale = 0.55
    Sound = $true
    AutoBreak = $false
    Effects = $true
    Theme = 'Escuro'
    Left = -1.0
    Top = -1.0
}
if (Test-Path -LiteralPath $settingsPath) {
    try {
        $saved = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        foreach ($key in @($settings.Keys)) {
            if ($null -ne $saved.$key) { $settings[$key] = $saved.$key }
        }
    } catch { }
}
$settings.FocusMinutes = [Math]::Max(1, [Math]::Min(180, [int]$settings.FocusMinutes))
$settings.BreakMinutes = [Math]::Max(1, [Math]::Min(60, [int]$settings.BreakMinutes))
$settings.Scale = [Math]::Max(0.35, [Math]::Min(1.5, [double]$settings.Scale))
$script:palettes = [ordered]@{
    Escuro = @{ Panel='#121F25'; Edge='#3B5555'; Text='#EEFFF5'; Muted='#B9CFC8'; Button='#2C4248'; Accent='#A6E9C5'; AccentInk='#142B25'; Break='#F5CB88'; BreakInk='#352810'; Track='#314246'; SettingsBg='#19292F'; Error='#FFB9B2' }
    Claro = @{ Panel='#FFFDF7'; Edge='#BFCFC8'; Text='#213B34'; Muted='#4F665E'; Button='#E2EAE5'; Accent='#326C59'; AccentInk='#FFFFFF'; Break='#8A571B'; BreakInk='#FFFFFF'; Track='#D9E4DC'; SettingsBg='#F3F6F1'; Error='#A43838' }
    Rosa = @{ Panel='#FFF0F5'; Edge='#DDA8BE'; Text='#5B2942'; Muted='#80566B'; Button='#F4D9E5'; Accent='#9E3D69'; AccentInk='#FFFFFF'; Break='#7D4C92'; BreakInk='#FFFFFF'; Track='#EBC9D9'; SettingsBg='#FFF5F8'; Error='#A43838' }
    Lavanda = @{ Panel='#29233C'; Edge='#71628D'; Text='#F5EFFF'; Muted='#D1C3E4'; Button='#433653'; Accent='#D5B6F5'; AccentInk='#30203F'; Break='#B3E6D3'; BreakInk='#183D32'; Track='#4F4162'; SettingsBg='#231E31'; Error='#FFB9C8' }
    'Terminal hacker' = @{ Panel='#07120D'; Edge='#3AD87D'; Text='#B8FFCF'; Muted='#69C58A'; Button='#112A1C'; Accent='#79F2A3'; AccentInk='#07120D'; Break='#FFD27C'; BreakInk='#211607'; Track='#173D27'; SettingsBg='#08150E'; Error='#FFAA91' }
    'HUD futurista' = @{ Panel='#091A2C'; Edge='#54D9F5'; Text='#E1FAFF'; Muted='#90BDCF'; Button='#193B52'; Accent='#62E7FF'; AccentInk='#062131'; Break='#FFBD76'; BreakInk='#32200B'; Track='#204458'; SettingsBg='#0A1829'; Error='#FFB1BB' }
    'Arcade retrô' = @{ Panel='#201434'; Edge='#F38FC9'; Text='#FFF4D8'; Muted='#DDBDEB'; Button='#46305E'; Accent='#FFDA71'; AccentInk='#30203D'; Break='#A2F1D5'; BreakInk='#183A31'; Track='#58416D'; SettingsBg='#1A112A'; Error='#FFB1BB' }
}
if (-not $palettes.Contains([string]$settings.Theme)) { $settings.Theme = 'Escuro' }
$script:themeMenuItems = @{}

$script:mode = 'Foco'
$script:running = $false
$script:remaining = [double]($settings.FocusMinutes * 60)
$script:total = $script:remaining
$script:deadline = [DateTime]::UtcNow
$script:completed = 0
$script:finished = $false
$script:settingsWindow = $null
$script:alertWindow = $null
$script:alertCount = 0
if ($ResumeStatePath -and -not $SelfTest) {
    $resume = Get-Content -LiteralPath $ResumeStatePath -Raw | ConvertFrom-Json
    if ($resume.Mode -notin @('Foco','Pausa') -or $resume.Total -lt 1 -or $resume.Total -gt 10800) { throw 'Invalid timer resume state' }
    $script:mode = [string]$resume.Mode
    $script:total = [double]$resume.Total
    $script:remaining = [Math]::Max(0, [Math]::Min($script:total, [double]$resume.Remaining))
    $script:completed = [Math]::Max(0, [int]$resume.Completed)
    $script:running = [bool]$resume.Running
    $script:finished = [bool]$resume.Finished
    if ($script:running) {
        $script:deadline = [DateTime]::Parse($resume.Deadline, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        $script:remaining = [Math]::Max(0, ($script:deadline - [DateTime]::UtcNow).TotalSeconds)
    }
}



function Save-Settings {
    try {
        $settings | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    } catch {
        $statusText.Text = 'Não foi possível salvar'
    }
}

function Reset-Timer([string]$newMode) {
    $script:mode = $newMode
    $script:running = $false
    $script:finished = $false
    $minutes = if ($newMode -eq 'Foco') { $settings.FocusMinutes } else { $settings.BreakMinutes }
    $script:total = [double]($minutes * 60)
    $script:remaining = $script:total
}

function Toggle-Timer {
    if ($script:running) {
        $script:remaining = [Math]::Max(0, ($script:deadline - [DateTime]::UtcNow).TotalSeconds)
        $script:running = $false
    } else {
        if ($script:remaining -le 0) {
            $next = if ($script:mode -eq 'Foco') { 'Pausa' } else { 'Foco' }
            Reset-Timer $next
        }
        $script:deadline = [DateTime]::UtcNow.AddSeconds($script:remaining)
        $script:running = $true
        $script:finished = $false
    }
}

function Update-Timer([DateTime]$now) {
    if (-not $script:running) { return }
    $script:remaining = [Math]::Max(0, ($script:deadline - $now).TotalSeconds)
    if ($script:remaining -le 0) {
        $script:running = $false
        $script:finished = $true
        if ($script:mode -eq 'Foco') {
            $script:completed++
            Show-EndAlert
        }
        if (-not $SelfTest -and $settings.Sound) { [System.Media.SystemSounds]::Asterisk.Play() }
        if ($script:mode -eq 'Foco' -and $settings.AutoBreak) {
            Reset-Timer 'Pausa'
            $script:deadline = $now.AddSeconds($script:remaining)
            $script:running = $true
        }
    }
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Pomobicho" Width="188" Height="290" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#DEE9E8"/>
      <Setter Property="Background" Value="#253538"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ButtonSurface" CornerRadius="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonSurface" Property="Opacity" Value="0.78"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonSurface" Property="Opacity" Value="0.55"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Setter Property="Tag" Value="9"/>
    </Style>
  </Window.Resources>
  <Viewbox Stretch="Uniform">
    <Grid Width="188" Height="290">
      <Canvas x:Name="PetCanvas" Width="188" Height="290" ToolTip="Arraste pelo gatinho. Clique direito para mais opções.">
        <Border x:Name="ThemeBackdrop" Canvas.Left="19" Canvas.Top="7" Width="150" Height="177" Background="#07120D" BorderBrush="#3AD87D" BorderThickness="1" Visibility="Collapsed"/>
        <Canvas x:Name="TerminalDecor" IsHitTestVisible="False" Visibility="Collapsed">
          <Rectangle Canvas.Left="27" Canvas.Top="32" Width="130" Height="1" Fill="#79F2A3" Opacity="0.3">
            <Rectangle.RenderTransform><TranslateTransform x:Name="ScanMotion"/></Rectangle.RenderTransform>
          </Rectangle>
          <Path Stroke="#173D27" StrokeThickness="0.6" Data="M 24,36 L 164,36 M 24,64 L 164,64 M 24,92 L 164,92 M 24,120 L 164,120 M 24,148 L 164,148 M 45,28 L 45,171 M 73,28 L 73,171 M 101,28 L 101,171 M 129,28 L 129,171 M 157,28 L 157,171"/>
          <TextBlock Canvas.Left="27" Canvas.Top="13" Text="CAT://FOCUS" FontFamily="Consolas" FontSize="8" Foreground="#79F2A3"/>
          <TextBlock Canvas.Left="27" Canvas.Top="169" Text="LOCAL / OFFLINE" FontFamily="Consolas" FontSize="6" Foreground="#69C58A"/>
          <Rectangle Canvas.Left="149" Canvas.Top="16" Width="5" Height="5" Fill="#79F2A3"/>
        </Canvas>
        <Canvas x:Name="HudDecor" IsHitTestVisible="False" Visibility="Collapsed">
          <Ellipse Canvas.Left="21" Canvas.Top="15" Width="146" Height="146" Stroke="#204458" StrokeThickness="1" StrokeDashArray="2 5"/>
          <Ellipse Canvas.Left="15" Canvas.Top="9" Width="158" Height="158" Stroke="#54D9F5" StrokeThickness="1" StrokeDashArray="24 56" RenderTransformOrigin="0.5,0.5">
            <Ellipse.RenderTransform><RotateTransform x:Name="HudRotation"/></Ellipse.RenderTransform>
          </Ellipse>
          <Path Stroke="#62E7FF" StrokeThickness="1.5" Data="M 12,48 L 12,32 L 28,32 M 160,32 L 176,32 L 176,48 M 12,128 L 12,144 L 28,144 M 160,144 L 176,144 L 176,128"/>
          <TextBlock Canvas.Left="57" Canvas.Top="171" Text="F O C U S  /  0 1" FontFamily="Consolas" FontSize="7" Foreground="#90BDCF"/>
        </Canvas>
        <Canvas x:Name="ArcadeDecor" IsHitTestVisible="False" Visibility="Collapsed">
          <Path Fill="#201434" Stroke="#F38FC9" StrokeThickness="2" Data="M 7,8 L 181,8 L 181,174 L 168,188 L 20,188 L 7,174 Z"/>
          <Rectangle Canvas.Left="18" Canvas.Top="18" Width="152" Height="23" Fill="#FFDA71"/>
          <TextBlock Canvas.Left="33" Canvas.Top="21" Text="P O M O  A R C A D E" FontFamily="Consolas" FontWeight="Bold" FontSize="9" Foreground="#30203D"/>
          <Rectangle Canvas.Left="20" Canvas.Top="48" Width="148" Height="126" Fill="#0E0C1A" Stroke="#806292" StrokeThickness="2"/>
          <Path Fill="#FFDA71" Data="M 29,59 L 33,59 L 33,55 L 37,55 L 37,59 L 41,59 L 41,63 L 37,63 L 37,67 L 33,67 L 33,63 L 29,63 Z M 147,154 L 151,154 L 151,150 L 155,150 L 155,154 L 159,154 L 159,158 L 155,158 L 155,162 L 151,162 L 151,158 L 147,158 Z"/>
        </Canvas>
        <Image x:Name="CatSprite" Canvas.Left="8" Canvas.Top="0" Width="172" Height="190" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
        <Path x:Name="HudPlate" Canvas.Left="6" Canvas.Top="184" Data="M 12,0 L 176,0 L 176,78 L 164,90 L 0,90 L 0,12 Z" Fill="#091A2C" Stroke="#54D9F5" StrokeThickness="1.2" Visibility="Collapsed"/>
        <Border x:Name="TimerCard" Canvas.Left="19" Canvas.Top="188" Width="150" Height="88" Background="#121F25" BorderBrush="#3B5555" BorderThickness="1.5" CornerRadius="18">
          <Grid>
          <Rectangle x:Name="Scanlines" IsHitTestVisible="False" Visibility="Collapsed" Opacity="0.06">
            <Rectangle.Fill>
              <DrawingBrush TileMode="Tile" Viewport="0,0,4,4" ViewportUnits="Absolute">
                <DrawingBrush.Drawing><GeometryDrawing Brush="#79F2A3" Geometry="M 0,0 L 4,0 L 4,1 L 0,1 Z"/></DrawingBrush.Drawing>
              </DrawingBrush>
            </Rectangle.Fill>
          </Rectangle>
          <Grid x:Name="TimerLayout" Margin="12,7,12,8">
            <Grid.RowDefinitions>
              <RowDefinition Height="14"/>
              <RowDefinition Height="33"/>
              <RowDefinition Height="4"/>
              <RowDefinition Height="21"/>
            </Grid.RowDefinitions>
            <TextBlock x:Name="ModeText" Text="FOCO" Foreground="#AAC3BD" FontFamily="Segoe UI" FontSize="9" FontWeight="SemiBold" HorizontalAlignment="Center"/>
            <TextBlock x:Name="ClockText" Grid.Row="1" Text="30:00" Foreground="#EEFFF5" FontFamily="Consolas" FontSize="29" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <Border x:Name="ProgressTrack" Grid.Row="2" Height="3" CornerRadius="1.5" Background="#314246">
              <Border x:Name="ProgressFill" Width="0" HorizontalAlignment="Left" Background="#A6E9C5" CornerRadius="1.5"/>
            </Border>
            <Grid Grid.Row="3" Margin="0,4,0,0">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="22"/><ColumnDefinition Width="22"/></Grid.ColumnDefinitions>
              <Button x:Name="StartButton" Content="Iniciar" FontSize="10" Background="#A6E9C5" Foreground="#142B25" Margin="0,0,4,0" ToolTip="Iniciar ou pausar"/>
              <Button x:Name="ResetButton" Grid.Column="1" Content="&#x21BA;" FontSize="14" Margin="0,0,3,0" ToolTip="Reiniciar este período"/>
              <Button x:Name="SettingsButton" Grid.Column="2" Content="&#x2699;" FontSize="12" ToolTip="Configurações"/>
            </Grid>
          </Grid>
          </Grid>
        </Border>
        <Border x:Name="StatusCard" Canvas.Left="23" Canvas.Top="275" Width="142" Height="15" Background="#DD122127" CornerRadius="6">
          <TextBlock x:Name="StatusText" Text="Um foco de cada vez" Foreground="#D3E4DF" FontFamily="Segoe UI" FontSize="8" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
      </Canvas>
    </Grid>
  </Viewbox>
</Window>
'@
$script:window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
foreach ($name in 'PetCanvas','ClockText','ModeText','StartButton','ResetButton','SettingsButton','ProgressFill','StatusText','CatSprite','TimerCard','ProgressTrack','StatusCard','ThemeBackdrop','TerminalDecor','HudDecor','HudPlate','Scanlines','TimerLayout','ArcadeDecor','ScanMotion','HudRotation') {
    Set-Variable -Scope Script -Name $name -Value $window.FindName($name)
}
$catImage = [Windows.Media.Imaging.BitmapImage]::new()
$catImage.BeginInit()
$catImage.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
$catImage.UriSource = [Uri](Join-Path $PSScriptRoot 'gatinho-laco.png')
$catImage.EndInit()
$catImage.Freeze()
$CatSprite.Source = $catImage

function Show-EndAlert([switch]$Preview) {
    if (-not $Preview) { $script:alertCount++ }
    if ($SelfTest -and -not $Preview) { return }
    if ($null -ne $script:alertWindow) { $script:alertWindow.Close() }
    [xml]$alertXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Pomobicho | Aviso de fim" Width="220" Height="260"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" Topmost="True" ShowInTaskbar="False"
        ShowActivated="False" WindowStartupLocation="Manual">
  <Viewbox Stretch="Uniform">
    <Grid Width="220" Height="260" Cursor="Hand" ToolTip="Clique para dispensar">
      <Image x:Name="AlertCat" Width="200" Height="208" VerticalAlignment="Top" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
      <Border x:Name="AlertCard" VerticalAlignment="Bottom" CornerRadius="12" BorderThickness="1" Padding="10,8">
        <StackPanel>
          <TextBlock x:Name="AlertTitle" Text="Foco concluído!" FontFamily="Segoe UI" FontSize="17" FontWeight="SemiBold" HorizontalAlignment="Center"/>
          <TextBlock x:Name="AlertHint" Text="Clique para dispensar" FontFamily="Segoe UI" FontSize="11" HorizontalAlignment="Center" Margin="0,3,0,0"/>
        </StackPanel>
      </Border>
    </Grid>
  </Viewbox>
</Window>
'@
    $script:alertWindow = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($alertXaml))
    $alertWindow.Owner = $window
    $alertWindow.FindName('AlertCat').Source = $catImage
    $alertWindow.FindName('AlertCard').Background = $themeBrushes.Panel
    $alertWindow.FindName('AlertCard').BorderBrush = $themeBrushes.Accent
    $alertWindow.FindName('AlertTitle').Foreground = $themeBrushes.Text
    $alertWindow.FindName('AlertHint').Foreground = $themeBrushes.Muted
    if ($Preview) { $alertWindow.FindName('AlertTitle').Text = 'Teste do aviso' }
    $alertWindow.Add_SourceInitialized({
        $handle = [Windows.Interop.WindowInteropHelper]::new($script:alertWindow).Handle
        [PomobichoPopup]::Configure($handle)
        $screen = [Windows.Forms.Screen]::AllScreens | Where-Object { $_.DeviceName -match '\\DISPLAY2$' } | Select-Object -First 1
        if ($null -eq $screen) { $screen = [Windows.Forms.Screen]::PrimaryScreen }
        $area = $screen.WorkingArea
        [PomobichoPopup]::PlaceAlert($handle, $area.Right - 244, $area.Bottom - 284, 220, 260)
    })
    $alertWindow.Add_MouseLeftButtonDown({ $script:alertWindow.Close() })
    $alertWindow.Add_PreviewKeyDown({
        param($sender,$eventArgs)
        if ($eventArgs.Key -eq [Windows.Input.Key]::Escape) { $script:alertWindow.Close() }
    })
    $alertWindow.Add_Closed({
        param($sender,$eventArgs)
        $sender.FindName('AlertCat').BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
        $script:alertWindow = $null
    })
    $pulse = [Windows.Media.Animation.DoubleAnimation]::new(1.0, 0.3, [TimeSpan]::FromSeconds(0.8))
    $pulse.AutoReverse = $true
    $pulse.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $alertWindow.FindName('AlertCat').BeginAnimation([Windows.UIElement]::OpacityProperty, $pulse)
    $alertWindow.Show()
}

function Set-PetSize {
    $window.Width = 188 * $settings.Scale
    $window.Height = 290 * $settings.Scale
}

function Keep-OnScreen {
    # Virtual desktop bounds include secondary monitors and negative coordinates.
    $left = [Windows.SystemParameters]::VirtualScreenLeft
    $top = [Windows.SystemParameters]::VirtualScreenTop
    $right = $left + [Windows.SystemParameters]::VirtualScreenWidth
    $bottom = $top + [Windows.SystemParameters]::VirtualScreenHeight
    $window.Left = [Math]::Max($left, [Math]::Min($right - $window.Width, $window.Left))
    $window.Top = [Math]::Max($top, [Math]::Min($bottom - $window.Height, $window.Top))
}

function Set-PetScale([double]$value) {
    $settings.Scale = [Math]::Round([Math]::Max(0.35, [Math]::Min(1.5, $value)), 2)
    Set-PetSize
    Keep-OnScreen
    if ($null -ne $script:settingsWindow) {
        $script:settingsWindow.FindName('SizeLabel').Text = 'Tamanho: {0}% (ao vivo)' -f [int]($settings.Scale * 100)
        if ([Math]::Abs($script:settingsWindow.FindName('SizeInput').Value - ($settings.Scale * 100)) -gt 0.1) {
            $script:settingsWindow.FindName('SizeInput').Value = [int][Math]::Round($settings.Scale * 100)
        }
    }
    if (-not $SelfTest) { Save-Settings }
}

function Apply-SettingsTheme {
    if ($null -eq $script:settingsWindow) { return }
    $settingsWindow.FindName('PopupCard').Background = $script:themeBrushes.SettingsBg
    $settingsWindow.FindName('PopupCard').BorderBrush = $script:themeBrushes.Edge
    $settingsWindow.Foreground = $script:themeBrushes.Text
    $settingsWindow.FindName('ClosePopup').Background = $script:themeBrushes.Button
    $settingsWindow.FindName('ClosePopup').Foreground = $script:themeBrushes.Text
    foreach ($name in 'SizeMinus','SizePlus') {
        $settingsWindow.FindName($name).Background = $script:themeBrushes.Button
        $settingsWindow.FindName($name).Foreground = $script:themeBrushes.Text
    }
    foreach ($name in 'SubtitleText','HelpText') {
        $settingsWindow.FindName($name).Foreground = $script:themeBrushes.Muted
    }
    foreach ($name in 'SoundInput','AutoInput','EffectsInput') {
        $settingsWindow.FindName($name).Foreground = $script:themeBrushes.Text
    }
    $settingsWindow.FindName('ErrorText').Foreground = $script:themeBrushes.Error
    $settingsWindow.FindName('SaveButton').Background = $script:themeBrushes.Accent
    $settingsWindow.FindName('SaveButton').Foreground = $script:themeBrushes.AccentInk
    $settingsWindow.FindName('ThemeInput').SelectedItem = [string]$settings.Theme
    $tech = $settings.Theme -in @('Terminal hacker','HUD futurista','Arcade retrô')
    foreach ($name in 'FocusInput','BreakInput') {
        $inputControl = $settingsWindow.FindName($name)
        $inputControl.Background = if ($tech) { $themeBrushes.Button } else { [Windows.Media.Brushes]::White }
        $inputControl.Foreground = if ($tech) { $themeBrushes.Text } else { [Windows.Media.Brushes]::Black }
        $inputControl.CaretBrush = $inputControl.Foreground
        $inputControl.BorderBrush = if ($tech) { $themeBrushes.Edge } else { [Windows.Media.Brushes]::DarkGray }
    }
    $settingsWindow.FontFamily = if ($tech) { 'Consolas' } else { 'Segoe UI' }
    $settingsWindow.FindName('PopupCard').CornerRadius = if ($tech) { 2 } else { 18 }
    $settingsWindow.FindName('PopupTitle').Text = switch ($settings.Theme) {
        'Terminal hacker' { '> pomo.config' }
        'HUD futurista' { 'PAINEL DE CONTROLE' }
        'Arcade retrô' { 'OPÇÕES DO JOGADOR' }
        default { 'Configurações' }
    }
    $settingsWindow.FindName('PopupTitle').FontSize = if ($tech) { 17 } else { 20 }
    $settingsWindow.FindName('SaveButton').Content = if ($tech) { '[ APLICAR AJUSTES ]' } else { 'Salvar ajustes' }
    $settingsWindow.FindName('SubtitleText').Text = if ($settings.Theme -eq 'Terminal hacker') { '# ajuste seu próximo ciclo' } else { 'Ajuste o próximo pomodoro.' }
}

function Apply-ThemeEffects {
    $ScanMotion.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $null)
    $HudRotation.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null)
    if (-not $settings.Effects) { return }
    if ($settings.Theme -eq 'Terminal hacker') {
        $animation = [Windows.Media.Animation.DoubleAnimation]::new(0, 132, [TimeSpan]::FromSeconds(6))
        $animation.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $ScanMotion.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $animation)
    } elseif ($settings.Theme -eq 'HUD futurista') {
        $animation = [Windows.Media.Animation.DoubleAnimation]::new(0, 360, [TimeSpan]::FromSeconds(28))
        $animation.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $HudRotation.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $animation)
    }
}

function Apply-ThemeLayout {
    $terminal = $settings.Theme -eq 'Terminal hacker'
    $hud = $settings.Theme -eq 'HUD futurista'
    $arcade = $settings.Theme -eq 'Arcade retrô'
    $tech = $terminal -or $hud -or $arcade
    $ArcadeDecor.Visibility = if ($arcade) { 'Visible' } else { 'Collapsed' }
    $ThemeBackdrop.Visibility = if ($terminal) { 'Visible' } else { 'Collapsed' }
    $TerminalDecor.Visibility = $ThemeBackdrop.Visibility
    $Scanlines.Visibility = $ThemeBackdrop.Visibility
    $HudDecor.Visibility = if ($hud) { 'Visible' } else { 'Collapsed' }
    $HudPlate.Visibility = $HudDecor.Visibility
    $TimerCard.CornerRadius = if ($arcade) { 4 } elseif ($tech) { 0 } else { 18 }
    $TimerCard.BorderThickness = if ($hud) { 0 } elseif ($terminal) { 1 } elseif ($arcade) { 2 } else { 1.5 }
    $TimerCard.Background = if ($hud) { [Windows.Media.Brushes]::Transparent } else { $themeBrushes.Panel }
    $TimerCard.Width = if ($tech) { 176 } else { 150 }
    [Windows.Controls.Canvas]::SetLeft($TimerCard, $(if ($tech) { 6 } else { 19 }))
    [Windows.Controls.Canvas]::SetTop($TimerCard, $(if ($tech) { 184 } else { 188 }))
    $TimerCard.Height = if ($tech) { 90 } else { 88 }
    $TimerLayout.Margin = if ($tech) { [Windows.Thickness]::new(13,7,13,8) } else { [Windows.Thickness]::new(12,7,12,8) }
    $ClockText.HorizontalAlignment = if ($terminal) { 'Left' } else { 'Center' }
    $ModeText.HorizontalAlignment = if ($terminal) { 'Left' } else { 'Center' }
    $ModeText.FontSize = if ($tech) { 8 } else { 9 }
    $StatusCard.CornerRadius = if ($tech) { 0 } else { 6 }
    $StatusCard.Width = if ($tech) { 176 } else { 142 }
    [Windows.Controls.Canvas]::SetLeft($StatusCard, $(if ($tech) { 6 } else { 23 }))
    $CatSprite.Width = if ($arcade) { 122 } elseif ($tech) { 142 } else { 172 }
    $CatSprite.Height = if ($arcade) { 122 } elseif ($tech) { 152 } else { 190 }
    [Windows.Controls.Canvas]::SetLeft($CatSprite, $(if ($arcade) { 33 } elseif ($tech) { 23 } else { 8 }))
    [Windows.Controls.Canvas]::SetTop($CatSprite, $(if ($terminal) { 25 } elseif ($hud) { 12 } elseif ($arcade) { 49 } else { 0 }))
    foreach ($control in $StartButton,$ModeText,$StatusText) {
        $control.FontFamily = if ($tech) { 'Consolas' } else { 'Segoe UI' }
    }
    foreach ($button in $StartButton,$ResetButton,$SettingsButton) {
        $button.Tag = if ($tech) { [Windows.CornerRadius]::new(0) } else { [Windows.CornerRadius]::new(9) }
    }
    $ResetButton.Content = if ($terminal) { 'R' } else { [char]0x21BA }
    $SettingsButton.Content = if ($terminal) { '>' } else { [char]0x2699 }
    Apply-ThemeEffects
}

function Set-PetTheme([string]$name, [switch]$Persist) {
    if (-not $palettes.Contains($name)) { $name = 'Escuro' }
    $settings.Theme = $name
    $script:themeBrushes = @{}
    foreach ($entry in $palettes[$name].GetEnumerator()) {
        $brush = [Windows.Media.BrushConverter]::new().ConvertFromString($entry.Value)
        $brush.Freeze()
        $script:themeBrushes[$entry.Key] = $brush
    }
    $TimerCard.Background = $themeBrushes.Panel
    $TimerCard.BorderBrush = $themeBrushes.Edge
    $ClockText.Foreground = $themeBrushes.Text
    $StatusCard.Background = $themeBrushes.Panel
    $StatusText.Foreground = $themeBrushes.Muted
    $ProgressTrack.Background = $themeBrushes.Track
    foreach ($button in $ResetButton,$SettingsButton) {
        $button.Background = $themeBrushes.Button
        $button.Foreground = $themeBrushes.Text
    }
    foreach ($key in $script:themeMenuItems.Keys) {
        $script:themeMenuItems[$key].IsChecked = ($key -eq $name)
    }
    Apply-ThemeLayout
    Apply-SettingsTheme
    Refresh-Display
    if ($Persist -and -not $SelfTest) { Save-Settings }
}

function Refresh-Display {
    $seconds = [int][Math]::Ceiling($script:remaining)
    $ClockText.Text = '{0:00}:{1:00}' -f [int][Math]::Floor($seconds / 60), ($seconds % 60)
    $ModeText.Text = $script:mode.ToUpperInvariant()
    $progressWidth = if ($settings.Theme -in @('Terminal hacker','HUD futurista','Arcade retrô')) { 146 } else { 123 }
    $ProgressFill.Width = $progressWidth * [Math]::Max(0, [Math]::Min(1, (1 - $script:remaining / $script:total)))
    $StartButton.Content = if ($script:running) { 'Pausar' } elseif ($script:finished) {
        if ($script:mode -eq 'Foco') { 'Pausa >' } else { 'Foco >' }
    } elseif ($script:remaining -lt $script:total) { 'Retomar' } else { 'Iniciar' }
    if ($settings.Theme -eq 'Terminal hacker') {
        $ModeText.Text = if ($script:mode -eq 'Foco') { 'user@pomo:~ foco' } else { 'user@pomo:~ pausa' }
        $StartButton.Content = '> ' + $StartButton.Content.ToString().ToLowerInvariant()
    } elseif ($settings.Theme -eq 'HUD futurista') {
        $ModeText.Text = 'CICLO / ' + $script:mode.ToUpperInvariant()
        $StartButton.Content = '[ ' + $StartButton.Content.ToString().ToUpperInvariant() + ' ]'
    } elseif ($settings.Theme -eq 'Arcade retrô') {
        $ModeText.Text = if ($script:mode -eq 'Foco') { 'FASE ' + ($completed + 1).ToString('00') } else { 'BONUS / DESCANSO' }
        if (-not $running -and -not $finished -and $remaining -eq $total) { $StartButton.Content = 'JOGAR' }
        else { $StartButton.Content = $StartButton.Content.ToString().ToUpperInvariant() }
    }
    $StatusText.Text = if ($script:finished) {
        if ($script:mode -eq 'Foco') { 'Boa! Hora de descansar.' } else { 'Pronto para mais um foco?' }
    } elseif ($script:mode -eq 'Pausa') { 'Respire. Solte os ombros.' } elseif ($script:running) {
        'Um foco de cada vez'
    } elseif ($script:remaining -lt $script:total) { 'Pausado. No seu tempo.' } else {
        '{0} pomodoro(s) nesta sessão' -f $script:completed
    }
    if ($settings.Theme -eq 'Terminal hacker') {
        $StatusText.Text = if ($finished) { '> ciclo concluído_' } elseif ($running) { '> executando ' + $script:mode.ToLowerInvariant() + '_' } else { '> aguardando comando_' }
    } elseif ($settings.Theme -eq 'HUD futurista') {
        $StatusText.Text = if ($finished) { 'CICLO CONCLUÍDO' } elseif ($running) { 'SESSÃO ATIVA / ' + $completed } else { 'SISTEMA PRONTO' }
    } elseif ($settings.Theme -eq 'Arcade retrô') {
        $StatusText.Text = if ($finished) { 'FASE COMPLETA!' } else { 'POMODOROS: ' + $completed.ToString('00') }
    }
    $brush = if ($script:mode -eq 'Pausa') { $themeBrushes.Break } else { $themeBrushes.Accent }
    $ModeText.Foreground = $themeBrushes.Muted
    $ProgressFill.Background = $brush
    $StartButton.Background = $brush
    $StartButton.Foreground = if ($script:mode -eq 'Pausa') { $themeBrushes.BreakInk } else { $themeBrushes.AccentInk }
}

function Register-PopupIgnoreRule {
    if ($SelfTest) { return }
    $komorebic = Get-Command komorebic.exe -ErrorAction SilentlyContinue
    if ($null -eq $komorebic -or -not (Get-Process komorebi -ErrorAction SilentlyContinue)) { return }
    # Register only our settings popup, before it is shown. Reapply when opening
    # so restarting/reloading the window manager does not require app setup.
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $komorebic.Source
    $info.Arguments = 'ignore-rule title "Pomobicho | Configurações"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = [Diagnostics.Process]::new()
    $proc.StartInfo = $info
    try {
        [void]$proc.Start()
        if (-not $proc.WaitForExit(2000)) { $proc.Kill() }
    } catch {
        # Native tool-window and popup styles remain effective without the CLI.
    } finally { $proc.Dispose() }
}

function Position-SettingsPopup {
    $handle = [Windows.Interop.WindowInteropHelper]::new($window).Handle
    $work = [PomobichoPopup]::WorkArea($handle)
    $source = [Windows.Interop.HwndSource]::FromHwnd($handle)
    $fromDevice = $source.CompositionTarget.TransformFromDevice
    $topLeft = $fromDevice.Transform([Windows.Point]::new($work.Left, $work.Top))
    $bottomRight = $fromDevice.Transform([Windows.Point]::new($work.Right, $work.Bottom))
    $settingsWindow.Height = [Math]::Min(520, $bottomRight.Y - $topLeft.Y - 24)
    $settingsWindow.Width = [Math]::Min(360, $bottomRight.X - $topLeft.X - 24)
    $popupLeft = $window.Left - $settingsWindow.Width - 12
    if ($popupLeft -lt $topLeft.X + 12) { $popupLeft = $window.Left + $window.Width + 12 }
    $settingsWindow.Left = [Math]::Max($topLeft.X + 12, [Math]::Min($popupLeft, $bottomRight.X - $settingsWindow.Width - 12))
    $settingsWindow.Top = [Math]::Max($topLeft.Y + 12, [Math]::Min($window.Top, $bottomRight.Y - $settingsWindow.Height - 12))
}

function Open-Settings {
    if ($null -ne $script:settingsWindow) { $script:settingsWindow.Activate(); return }
    Register-PopupIgnoreRule
    [xml]$sx = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Pomobicho | Configurações" Width="360" Height="520"
        WindowStyle="None" AllowsTransparency="True" ShowInTaskbar="False"
        ResizeMode="NoResize" WindowStartupLocation="Manual" Topmost="True"
        Background="Transparent" FontFamily="Segoe UI" Foreground="#1B3434">
  <Border x:Name="PopupCard" Background="#F3F6F1" BorderBrush="#BFCFC8" BorderThickness="1" CornerRadius="18" Padding="20">
  <DockPanel>
    <Grid x:Name="PopupHeader" DockPanel.Dock="Top" Margin="0,0,0,10" Background="Transparent" Cursor="SizeAll">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="32"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="PopupTitle" Text="Configurações" FontSize="20" FontWeight="SemiBold" VerticalAlignment="Center"/>
      <Button x:Name="ClosePopup" Grid.Column="1" Content="&#x00D7;" FontSize="20" Width="30" Height="30" BorderThickness="0" Cursor="Hand" ToolTip="Fechar (Esc)"/>
    </Grid>
    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
  <StackPanel>
    <TextBlock x:Name="SubtitleText" Text="Ajuste o próximo pomodoro." Margin="0,4,0,19" Foreground="#59706A"/>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <StackPanel Margin="0,0,10,0">
        <TextBlock Text="Foco (1 a 180 min)" Margin="0,0,0,5"/>
        <TextBox x:Name="FocusInput" Padding="8" FontSize="16"/>
      </StackPanel>
      <StackPanel Grid.Column="1">
        <TextBlock Text="Pausa (1 a 60 min)" Margin="0,0,0,5"/>
        <TextBox x:Name="BreakInput" Padding="8" FontSize="16"/>
      </StackPanel>
    </Grid>
    <TextBlock x:Name="SizeLabel" Text="Tamanho do bichinho" Margin="0,17,0,7"/>
    <Grid Height="30">
      <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="*"/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
      <Button x:Name="SizeMinus" Content="&#x2212;" FontSize="18" BorderThickness="0" Cursor="Hand" ToolTip="Diminuir 5%"/>
      <Slider x:Name="SizeInput" Grid.Column="1" Minimum="35" Maximum="150" TickFrequency="5"
              SmallChange="5" LargeChange="10" IsSnapToTickEnabled="True" IsMoveToPointEnabled="True"
              VerticalAlignment="Center" Height="26" Margin="9,0" Cursor="Hand"
              ToolTip="Clique na barra ou arraste. Use as setas para ajustar de 5 em 5%."/>
      <Button x:Name="SizePlus" Grid.Column="2" Content="+" FontSize="18" BorderThickness="0" Cursor="Hand" ToolTip="Aumentar 5%"/>
    </Grid>
    <TextBlock Text="Tema (muda e salva na hora)" Margin="0,14,0,5"/>
    <ComboBox x:Name="ThemeInput" Padding="7" Foreground="#202020" Background="White"/>
    <CheckBox x:Name="SoundInput" Content="Tocar som ao terminar" Margin="0,17,0,0"/>
    <CheckBox x:Name="AutoInput" Content="Começar a pausa automaticamente" Margin="0,12,0,0"/>
    <CheckBox x:Name="EffectsInput" Content="Efeitos visuais (ao vivo)" Margin="0,12,0,0"/>
    <TextBlock x:Name="HelpText" Text="Arraste pelo gatinho para mover.&#x0a;Ctrl + rodinha do mouse ajusta o tamanho." FontSize="11" Foreground="#59706A" Margin="0,17,0,0"/>
    <TextBlock x:Name="ErrorText" Foreground="#AA4038" FontSize="11" Height="32" TextWrapping="Wrap" Margin="0,5,0,0"/>
    <Button x:Name="SaveButton" Content="Salvar ajustes" Padding="10" Background="#254B42" Foreground="White" BorderThickness="0" Cursor="Hand"/>
  </StackPanel>
    </ScrollViewer>
  </DockPanel>
  </Border>
</Window>
'@
    $script:settingsWindow = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $sx))
    $settingsWindow.Owner = $window
    $settingsWindow.Add_SourceInitialized({
        $handle = [Windows.Interop.WindowInteropHelper]::new($script:settingsWindow).Handle
        [PomobichoPopup]::Configure($handle)
    })
    Position-SettingsPopup
    $settingsWindow.FindName('ClosePopup').Add_Click({ $script:settingsWindow.Close() })
    $settingsWindow.FindName('PopupHeader').Add_MouseLeftButtonDown({
        if ([Windows.Input.Mouse]::LeftButton -eq [Windows.Input.MouseButtonState]::Pressed) {
            $script:settingsWindow.DragMove()
        }
    })
    $settingsWindow.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq [Windows.Input.Key]::Escape) {
            $eventArgs.Handled = $true
            $script:settingsWindow.Close()
        }
    })
    foreach ($name in $palettes.Keys) { [void]$settingsWindow.FindName('ThemeInput').Items.Add($name) }
    Apply-SettingsTheme
    $settingsWindow.FindName('ThemeInput').Add_SelectionChanged({
        param($sender, $eventArgs)
        if ($null -ne $sender.SelectedItem -and $settings.Theme -ne [string]$sender.SelectedItem) {
            Set-PetTheme ([string]$sender.SelectedItem) -Persist
        }
    })
    $settingsWindow.FindName('FocusInput').Text = [string]$settings.FocusMinutes
    $settingsWindow.FindName('BreakInput').Text = [string]$settings.BreakMinutes
    $settingsWindow.FindName('SizeInput').Value = [int][Math]::Round($settings.Scale * 100)
    $settingsWindow.FindName('SizeLabel').Text = 'Tamanho: {0}% (ao vivo)' -f [int]($settings.Scale * 100)
    $settingsWindow.FindName('SizeInput').Add_ValueChanged({
        param($sender, $eventArgs)
        Set-PetScale ([double]$sender.Value / 100.0)
    })
    $settingsWindow.FindName('SizeMinus').Add_Click({ Set-PetScale ($settings.Scale - 0.05) })
    $settingsWindow.FindName('SizePlus').Add_Click({ Set-PetScale ($settings.Scale + 0.05) })
    $settingsWindow.FindName('SoundInput').IsChecked = $settings.Sound
    $settingsWindow.FindName('AutoInput').IsChecked = $settings.AutoBreak
    $settingsWindow.FindName('EffectsInput').IsChecked = $settings.Effects
    $settingsWindow.FindName('EffectsInput').Add_Click({
        $settings.Effects = [bool]$script:settingsWindow.FindName('EffectsInput').IsChecked
        Apply-ThemeEffects
        if (-not $SelfTest) { Save-Settings }
    })
    $settingsWindow.FindName('SaveButton').Add_Click({
        $focus = 0; $break = 0
        $okFocus = [int]::TryParse($script:settingsWindow.FindName('FocusInput').Text, [ref]$focus)
        $okBreak = [int]::TryParse($script:settingsWindow.FindName('BreakInput').Text, [ref]$break)
        if (-not $okFocus -or -not $okBreak -or $focus -lt 1 -or $focus -gt 180 -or $break -lt 1 -or $break -gt 60) {
            $script:settingsWindow.FindName('ErrorText').Text = 'Use minutos inteiros: foco de 1 a 180; pausa de 1 a 60.'
            return
        }
        $settings.FocusMinutes = $focus
        $settings.BreakMinutes = $break
        $settings.Scale = [double]$script:settingsWindow.FindName('SizeInput').Value / 100.0
        $settings.Sound = [bool]$script:settingsWindow.FindName('SoundInput').IsChecked
        $settings.AutoBreak = [bool]$script:settingsWindow.FindName('AutoInput').IsChecked
        # Preserve an active or paused timer; apply new durations to the next period.
        if (-not $script:running -and $script:remaining -eq $script:total) { Reset-Timer $script:mode }
        Set-PetSize
        Keep-OnScreen
        Save-Settings
        Refresh-Display
        $script:settingsWindow.Close()
    })
    $settingsWindow.Add_Closed({ $script:settingsWindow = $null })
    $settingsWindow.Show()
}

$StartButton.Add_Click({ Toggle-Timer; Refresh-Display })
$ResetButton.Add_Click({ Reset-Timer $script:mode; Refresh-Display })
$SettingsButton.Add_Click({ Open-Settings })
$window.Add_PreviewMouseWheel({
    param($sender, $eventArgs)
    if (([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -ne 0) {
        $step = if ($eventArgs.Delta -gt 0) { 0.05 } else { -0.05 }
        Set-PetScale ($settings.Scale + $step)
        $eventArgs.Handled = $true
    }
})
$PetCanvas.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    if ($eventArgs.Handled) { return }
    try {
        $window.DragMove()
        Keep-OnScreen
        $settings.Left = $window.Left
        $settings.Top = $window.Top
        Save-Settings
    } catch { }
})
$menu = New-Object Windows.Controls.ContextMenu
foreach ($label in 'Configurações','Diminuir tamanho','Aumentar tamanho','Testar aviso no monitor 2','Iniciar foco','Iniciar pausa','Fechar bichinho') {
    $item = New-Object Windows.Controls.MenuItem
    $item.Header = $label
    $item.Add_Click({
        param($sender, $eventArgs)
        switch ($sender.Header) {
            'Configurações' { Open-Settings }
            'Diminuir tamanho' { Set-PetScale ($settings.Scale - 0.05) }
            'Aumentar tamanho' { Set-PetScale ($settings.Scale + 0.05) }
            'Testar aviso no monitor 2' { Show-EndAlert -Preview }
            'Iniciar foco' { Reset-Timer 'Foco'; Toggle-Timer; Refresh-Display }
            'Iniciar pausa' { Reset-Timer 'Pausa'; Toggle-Timer; Refresh-Display }
            'Fechar bichinho' { $window.Close() }
        }
    })
    [void]$menu.Items.Add($item)
}
$PetCanvas.ContextMenu = $menu
$themesMenu = New-Object Windows.Controls.MenuItem
$themesMenu.Header = 'Tema'
foreach ($name in $palettes.Keys) {
    $themeItem = New-Object Windows.Controls.MenuItem
    $themeItem.Header = $name
    $themeItem.IsCheckable = $true
    $themeItem.Add_Click({
        param($sender, $eventArgs)
        Set-PetTheme ([string]$sender.Header) -Persist
    })
    $script:themeMenuItems[$name] = $themeItem
    [void]$themesMenu.Items.Add($themeItem)
}
$menu.Items.Insert(1, $themesMenu)

Set-PetSize
$workArea = [Windows.SystemParameters]::WorkArea
if ($settings.Left -eq -1 -and $settings.Top -eq -1) {
    $window.Left = $workArea.Right - $window.Width - 30
    $window.Top = $workArea.Bottom - $window.Height - 30
} else {
    $window.Left = [double]$settings.Left
    $window.Top = [double]$settings.Top
}
Keep-OnScreen
Set-PetTheme ([string]$settings.Theme)

if ($SelfTest) {
    $settings.Scale = 0.55
    Set-PetSize
    $settings.FocusMinutes = 30
    $settings.BreakMinutes = 5
    $settings.AutoBreak = $false
    Reset-Timer 'Foco'
    if ($remaining -ne 1800) { throw 'Default duration failed' }
    Toggle-Timer
    if (-not $running) { throw 'Start failed' }
    Update-Timer ($deadline.AddSeconds(-60))
    if ([Math]::Abs($remaining - 60) -gt 0.1) { throw 'Countdown failed' }
    Update-Timer ($deadline.AddSeconds(1))
    if ($running -or -not $finished -or $completed -ne 1) { throw 'Completion failed' }
    if ($alertCount -ne 1) { throw 'Completion alert failed' }
    Update-Timer ($deadline.AddSeconds(2))
    if ($alertCount -ne 1) { throw 'Completion alert repeated' }
    Toggle-Timer
    if ($mode -ne 'Pausa' -or $remaining -ne 300 -or -not $running) { throw 'Break transition failed' }
    Toggle-Timer
    if ($running -or $remaining -le 299) { throw 'Pause failed' }
    Toggle-Timer
    if (-not $running) { throw 'Resume failed' }
    Update-Timer ($deadline.AddSeconds(1))
    if ($completed -ne 1) { throw 'Break counted as focus' }
    if ($alertCount -ne 1) { throw 'Break triggered focus alert' }
    $settings.AutoBreak = $true
    Reset-Timer 'Foco'
    Toggle-Timer
    Update-Timer ($deadline.AddSeconds(1))
    if ($mode -ne 'Pausa' -or -not $running -or $remaining -ne 300) { throw 'Automatic break failed' }
    if ($alertCount -ne 2) { throw 'Auto break suppressed focus alert' }
    $settings.AutoBreak = $false
    Reset-Timer 'Foco'
    $script:completed = 0
    Refresh-Display
    if ($ClockText.Text -ne '30:00') { throw 'Clock format failed' }
    # Test actual settings controls and validation without waiting for user input.
    $window.Show()
    Show-EndAlert -Preview
    if (-not $alertWindow.FindName('AlertCat').HasAnimatedProperties) { throw 'Alert blink failed' }
    $alertWindow.Close()
    if ($null -ne $script:alertWindow) { throw 'Alert cleanup failed' }
    Open-Settings
    $popupHandle = [Windows.Interop.WindowInteropHelper]::new($settingsWindow).Handle
    $popupExStyle = [PomobichoPopup]::GetWindowLong($popupHandle, -20)
    $popupStyle = [PomobichoPopup]::GetWindowLong($popupHandle, -16)
    if (($popupExStyle -band 0x80) -eq 0 -or ($popupExStyle -band 0x40000) -ne 0 -or $settingsWindow.ShowInTaskbar) {
        throw 'Popup tool-window style failed'
    }
    if (($popupStyle -band 0x00C00000) -ne 0 -or ($popupStyle -band [int]::MinValue) -eq 0) {
        throw 'Popup native style failed'
    }
    Toggle-Timer
    $testDeadline = $script:deadline
    foreach ($themeName in $palettes.Keys) {
        $settingsWindow.FindName('ThemeInput').SelectedItem = $themeName
        if ($settings.Theme -ne $themeName -or $ClockText.Foreground.Color.ToString() -ne ('#FF' + $palettes[$themeName].Text.Substring(1))) {
            throw "Theme selection failed: $themeName"
        }
        $expectedWidth = if ($themeName -in @('Terminal hacker','HUD futurista','Arcade retrô')) { 176 } else { 150 }
        if ($TimerCard.Width -ne $expectedWidth) { throw "Theme geometry failed: $themeName" }
        if (-not $themeMenuItems[$themeName].IsChecked) { throw 'Theme menu did not synchronize' }
        if (-not $running -or $deadline -ne $testDeadline) { throw 'Theme change affected running timer' }
        if ($PreviewPath -and $themeName -in @('Terminal hacker','HUD futurista','Arcade retrô')) {
            $window.UpdateLayout()
            $variantBitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int][Math]::Ceiling($window.Width * 2)),([int][Math]::Ceiling($window.Height * 2)),192,192,([Windows.Media.PixelFormats]::Pbgra32)
            $variantBitmap.Render($window.Content)
            $variantEncoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
            $variantEncoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($variantBitmap))
            $variantPath = [IO.Path]::ChangeExtension($PreviewPath, ($themeName.Replace(' ', '-') + '.png'))
            $variantStream = [IO.File]::Open($variantPath, [IO.FileMode]::Create)
            try { $variantEncoder.Save($variantStream) } finally { $variantStream.Dispose() }
        }
    }
    $originalSettingsPath = $script:settingsPath
    if ($PreviewPath) {
        $script:settingsPath = [IO.Path]::ChangeExtension($PreviewPath, 'preferences-test.json')
        try {
            Save-Settings
            $savedTest = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
            if ($savedTest.Theme -ne 'Arcade retrô') { throw 'Theme persistence failed' }
        } finally { $script:settingsPath = $originalSettingsPath }
    }
    Set-PetTheme 'Rosa'
    if ($TimerCard.CornerRadius.TopLeft -ne 18 -or $HudPlate.Visibility -ne 'Collapsed' -or $CatSprite.Width -ne 172) {
        throw 'Classic theme restoration failed'
    }
    Set-PetTheme 'Terminal hacker'
    $settingsWindow.FindName('EffectsInput').IsChecked = $true
    $settingsWindow.FindName('EffectsInput').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    if (-not $ScanMotion.HasAnimatedProperties) { throw 'Terminal animation failed' }
    $settingsWindow.FindName('EffectsInput').IsChecked = $false
    $settingsWindow.FindName('EffectsInput').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    if ($ScanMotion.HasAnimatedProperties -or $HudRotation.HasAnimatedProperties) { throw 'Effects disable failed' }
    Set-PetTheme 'HUD futurista'
    if ($HudRotation.HasAnimatedProperties) { throw 'Disabled effects restarted on theme change' }
    $settingsWindow.FindName('EffectsInput').IsChecked = $true
    $settingsWindow.FindName('EffectsInput').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    if (-not $HudRotation.HasAnimatedProperties) { throw 'HUD animation failed' }
    if (-not $running -or $deadline -ne $testDeadline) { throw 'Effects changed active timer' }
    Set-PetTheme 'Arcade retrô'
    if ($ScanMotion.HasAnimatedProperties -or $HudRotation.HasAnimatedProperties) { throw 'Hidden animations were not stopped' }
    Reset-Timer 'Foco'
    Refresh-Display
    $settingsWindow.FindName('SizeInput').Value = 35
    if ([Math]::Abs($window.Width - 65.8) -gt 0.6) { throw 'Live minimum resize failed' }
    $settingsWindow.FindName('SizeInput').Value = 55
    if ([Math]::Abs($window.Height - 159.5) -gt 0.6) { throw 'Live resize failed' }
    $settingsWindow.FindName('SizePlus').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    if ($settings.Scale -ne 0.6 -or $settingsWindow.FindName('SizeInput').Value -ne 60) { throw 'Plus size button failed' }
    $settingsWindow.FindName('SizeMinus').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    if ($settings.Scale -ne 0.55 -or $settingsWindow.FindName('SizeInput').Value -ne 55) { throw "Minus size button failed: scale=$($settings.Scale) slider=$($settingsWindow.FindName('SizeInput').Value)" }
    if ($PreviewPath) {
        $settingsWindow.UpdateLayout()
        $settingsBitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int][Math]::Ceiling($settingsWindow.Width * 2)),([int][Math]::Ceiling($settingsWindow.Height * 2)),192,192,([Windows.Media.PixelFormats]::Pbgra32)
        $settingsBitmap.Render($settingsWindow)
        $settingsEncoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $settingsEncoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($settingsBitmap))
        $settingsPreview = [IO.Path]::ChangeExtension($PreviewPath, 'settings.png')
        $settingsStream = [IO.File]::Open($settingsPreview, [IO.FileMode]::Create)
        try { $settingsEncoder.Save($settingsStream) } finally { $settingsStream.Dispose() }
    }
    $settingsWindow.FindName('FocusInput').Text = '0'
    $settingsWindow.FindName('SaveButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    if ($settingsWindow.FindName('ErrorText').Text -eq '') { throw 'Settings validation failed' }
    $settingsWindow.Close()
    if ($PreviewPath) {
        $window.Show()
        $window.UpdateLayout()
        $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int][Math]::Ceiling($window.Width * 2)),([int][Math]::Ceiling($window.Height * 2)),192,192,([Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($window.Content)
        $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream = [IO.File]::Open($PreviewPath, [IO.FileMode]::Create)
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
    }
    $window.Close()
    Write-Output 'PASS: start, countdown, completion, pause, resume, focus/break transition, automatic break, display and settings validation.'
    exit 0
}

$createdNew = $false
$mutex = New-Object Threading.Mutex($true, 'Local\PomobichoDesktopTimer', [ref]$createdNew)
if (-not $createdNew) { $mutex.Dispose(); exit 0 }
$script:timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({
    $now = [DateTime]::UtcNow
    Update-Timer $now
    Refresh-Display
    $ModeText.Opacity = if ($script:finished) { 0.5 + 0.5 * [Math]::Abs([Math]::Sin($now.TimeOfDay.TotalSeconds * 3)) } else { 1 }
})
$window.Add_Closed({
    $timer.Stop()
    if ($null -ne $script:settingsWindow) { $script:settingsWindow.Close() }
    if ($null -ne $script:alertWindow) { $script:alertWindow.Close() }
    $settings.Left = $window.Left
    $settings.Top = $window.Top
    Save-Settings
})
try {
    if ($ShowSettings) { $window.Add_ContentRendered({ Open-Settings }) }
    if ($PreviewAlert) { $window.Add_ContentRendered({ Show-EndAlert -Preview }) }
    $timer.Start()
    [void]$window.ShowDialog()
} finally {
    $timer.Stop()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
