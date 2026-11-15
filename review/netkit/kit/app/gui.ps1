# gui.ps1 — окно комплекта LibreWolf-USB: векторный логотип TempleOS с настоящей
# анимацией (ткань колышется, чаши весов качаются, раз в 30 с смена образа)
# и кнопки для всех действий. Консольное меню остаётся запасным вариантом.
$ErrorActionPreference = 'Stop'

try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
} catch {
    exit 1
}

$App     = $PSScriptRoot
$Root    = Split-Path -Parent $App
$Vpn     = Join-Path $Root 'vpn'
$Cfg     = Join-Path $Vpn 'config.json'
$SubFile = Join-Path $Vpn 'sub.txt'

$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TempleOS - LibreWolf-USB" Height="640" Width="1000"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        Background="#0B0F14" Foreground="#E8EAED" FontFamily="Segoe UI">
  <Window.Resources>
    <LinearGradientBrush x:Key="GoldBrush" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#FFF3A0" Offset="0"/>
      <GradientStop Color="#FFD23F" Offset="0.5"/>
      <GradientStop Color="#C98A00" Offset="1"/>
    </LinearGradientBrush>
    <LinearGradientBrush x:Key="ShroudBrush" StartPoint="0,0" EndPoint="0,1">
      <GradientStop Color="#FFFFFF" Offset="0"/>
      <GradientStop Color="#D8DEE8" Offset="1"/>
    </LinearGradientBrush>
    <LinearGradientBrush x:Key="BladeBrush" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#F4F7FB" Offset="0"/>
      <GradientStop Color="#9AA6B5" Offset="1"/>
    </LinearGradientBrush>

    <Style TargetType="Button" x:Key="MenuButton">
      <Setter Property="Background" Value="#141B24"/>
      <Setter Property="Foreground" Value="#E8EAED"/>
      <Setter Property="BorderBrush" Value="#24303D"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="16,10"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1D2734"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="#3B7EA1"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#243244"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="TextBlock" x:Key="Caption">
      <Setter Property="Foreground" Value="#8B98A5"/>
      <Setter Property="FontSize" Value="12"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="420"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- ================= логотип ================= -->
    <Border Grid.Column="0" Background="#0A1A1E" BorderBrush="#13262C" BorderThickness="0,0,1,0">
      <Viewbox Stretch="Uniform" Margin="18">
        <Canvas Width="360" Height="440">
          <!-- мягкое свечение -->
          <Ellipse Canvas.Left="60" Canvas.Top="90" Width="240" Height="260" Opacity="0.16">
            <Ellipse.Fill>
              <RadialGradientBrush>
                <GradientStop Color="#FFF0A0" Offset="0"/>
                <GradientStop Color="#00333C40" Offset="1"/>
              </RadialGradientBrush>
            </Ellipse.Fill>
            <Ellipse.Effect>
              <BlurEffect Radius="40"/>
            </Ellipse.Effect>
          </Ellipse>

          <!-- ======== КРЕСТ ======== -->
          <Canvas x:Name="CrossGroup" Width="360" Height="440" Opacity="1">
            <Canvas.RenderTransform>
              <ScaleTransform x:Name="CrossScale" ScaleX="1" ScaleY="1" CenterX="180" CenterY="220"/>
            </Canvas.RenderTransform>

            <!-- тень -->
            <Rectangle Canvas.Left="163" Canvas.Top="52" Width="52" Height="310" RadiusX="4"
                       Fill="#05090B" Opacity="0.55"/>
            <Rectangle Canvas.Left="60" Canvas.Top="132" Width="252" Height="38" RadiusX="4"
                       Fill="#05090B" Opacity="0.55"/>

            <!-- вертикальная балка -->
            <Rectangle Canvas.Left="152" Canvas.Top="40" Width="56" Height="310" RadiusX="5" Fill="{StaticResource GoldBrush}">
              <Rectangle.Effect>
                <DropShadowEffect Color="#FFC93C" BlurRadius="26" ShadowDepth="0" Opacity="0.55"/>
              </Rectangle.Effect>
            </Rectangle>
            <Rectangle Canvas.Left="196" Canvas.Top="40" Width="12" Height="310" Fill="#A87000" Opacity="0.55"/>

            <!-- перекладина -->
            <Rectangle Canvas.Left="50" Canvas.Top="120" Width="260" Height="38" RadiusX="5" Fill="{StaticResource GoldBrush}"/>
            <Rectangle Canvas.Left="50" Canvas.Top="148" Width="260" Height="10" Fill="#A87000" Opacity="0.55"/>

            <!-- плащаница: три полотнища, каждое колышется -->
            <Path Fill="{StaticResource ShroudBrush}">
              <Path.Data>
                <PathGeometry Figures="M 92,104 C 130,78 230,78 268,104 L 268,120 C 230,102 130,102 92,120 Z"/>
              </Path.Data>
              <Path.RenderTransform>
                <SkewTransform x:Name="ShroudTopSkew" CenterX="180" CenterY="104"/>
              </Path.RenderTransform>
            </Path>

            <Path Fill="{StaticResource ShroudBrush}" Opacity="0.95">
              <Path.Data>
                <PathGeometry Figures="M 117,118 L 147,118 L 145,236 C 137,246 126,246 119,236 Z"/>
              </Path.Data>
              <Path.RenderTransform>
                <SkewTransform x:Name="ShroudLeftSkew" CenterX="132" CenterY="118"/>
              </Path.RenderTransform>
            </Path>

            <Path Fill="{StaticResource ShroudBrush}" Opacity="0.95">
              <Path.Data>
                <PathGeometry Figures="M 213,118 L 243,118 L 241,236 C 234,246 223,246 215,236 Z"/>
              </Path.Data>
              <Path.RenderTransform>
                <SkewTransform x:Name="ShroudRightSkew" CenterX="228" CenterY="118"/>
              </Path.RenderTransform>
            </Path>

            <!-- складки -->
            <Path Stroke="#AEB9C6" StrokeThickness="2" Opacity="0.7">
              <Path.Data>
                <PathGeometry Figures="M 128,132 L 126,224"/>
              </Path.Data>
              <Path.RenderTransform>
                <SkewTransform x:Name="FoldLeftSkew" CenterX="128" CenterY="118"/>
              </Path.RenderTransform>
            </Path>
            <Path Stroke="#AEB9C6" StrokeThickness="2" Opacity="0.7">
              <Path.Data>
                <PathGeometry Figures="M 228,132 L 234,224"/>
              </Path.Data>
              <Path.RenderTransform>
                <SkewTransform x:Name="FoldRightSkew" CenterX="228" CenterY="118"/>
              </Path.RenderTransform>
            </Path>
          </Canvas>

          <!-- ======== ВЕСЫ И МЕЧ ======== -->
          <Canvas x:Name="ScalesGroup" Width="360" Height="440" Opacity="0">
            <Canvas.RenderTransform>
              <ScaleTransform x:Name="ScalesScale" ScaleX="1" ScaleY="1" CenterX="180" CenterY="220"/>
            </Canvas.RenderTransform>

            <!-- меч -->
            <Canvas>
              <Canvas.RenderTransform>
                <RotateTransform Angle="-38" CenterX="180" CenterY="300"/>
              </Canvas.RenderTransform>
              <Rectangle Canvas.Left="172" Canvas.Top="180" Width="18" Height="230" RadiusX="4" Fill="{StaticResource BladeBrush}">
                <Rectangle.Effect>
                  <DropShadowEffect Color="#BFE9FF" BlurRadius="18" ShadowDepth="0" Opacity="0.5"/>
                </Rectangle.Effect>
              </Rectangle>
              <Rectangle Canvas.Left="150" Canvas.Top="400" Width="62" Height="14" RadiusX="4" Fill="{StaticResource GoldBrush}"/>
              <Rectangle Canvas.Left="174" Canvas.Top="410" Width="14" Height="34" RadiusX="5" Fill="#A87000"/>
            </Canvas>

            <!-- шатёр -->
            <Polygon Points="180,54 292,116 68,116" Fill="{StaticResource GoldBrush}">
              <Polygon.Effect>
                <DropShadowEffect Color="#FFC93C" BlurRadius="24" ShadowDepth="0" Opacity="0.5"/>
              </Polygon.Effect>
            </Polygon>
            <Polygon Points="180,54 180,116 68,116" Fill="#A87000" Opacity="0.35"/>

            <!-- левая чаша -->
            <Line X1="122" Y1="116" X2="122" Y2="196" Stroke="#8B98A5" StrokeThickness="2" x:Name="ChainLeft"/>
            <Canvas>
              <Canvas.RenderTransform>
                <TranslateTransform x:Name="CupLeftShift" Y="0"/>
              </Canvas.RenderTransform>
              <Path Fill="{StaticResource GoldBrush}" Stroke="#C98A00" StrokeThickness="2"
                    Data="M 88,196 Q 122,226 156,196 L 156,190 L 88,190 Z"/>
            </Canvas>

            <!-- правая чаша -->
            <Line X1="238" Y1="116" X2="238" Y2="196" Stroke="#8B98A5" StrokeThickness="2" x:Name="ChainRight"/>
            <Canvas>
              <Canvas.RenderTransform>
                <TranslateTransform x:Name="CupRightShift" Y="0"/>
              </Canvas.RenderTransform>
              <Path Fill="{StaticResource GoldBrush}" Stroke="#C98A00" StrokeThickness="2"
                    Data="M 204,196 Q 238,226 272,196 L 272,190 L 204,190 Z"/>
            </Canvas>
          </Canvas>

          <!-- подпись -->
          <TextBlock Canvas.Left="0" Canvas.Top="392" Width="360" Text="TempleOS" TextAlignment="Center"
                     FontFamily="Consolas" FontSize="26">
            <TextBlock.Foreground>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                <GradientStop Color="#FFD23F" Offset="0"/>
                <GradientStop Color="#FFFFFF" Offset="0.5"/>
                <GradientStop Color="#FFD23F" Offset="1"/>
              </LinearGradientBrush>
            </TextBlock.Foreground>
          </TextBlock>
        </Canvas>
      </Viewbox>
    </Border>

    <!-- ================= правая панель ================= -->
    <Grid Grid.Column="1" Margin="26,22,26,18">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <StackPanel Grid.Row="0">
        <TextBlock Text="LibreWolf-USB" FontSize="26" FontWeight="Light" Foreground="#FFFFFF"/>
        <TextBlock Text="браузер без прямого выхода · TempleOS 5.03" Style="{StaticResource Caption}" Margin="0,2,0,0"/>
      </StackPanel>

      <Border Grid.Row="1" Background="#101821" BorderBrush="#1B2632" BorderThickness="1"
              CornerRadius="10" Padding="16,12" Margin="0,16,0,0">
        <StackPanel>
          <TextBlock x:Name="TxtBrowser" Text="Браузер  : проверяю..." Foreground="#C6D0DA" FontFamily="Consolas" FontSize="12"/>
          <TextBlock x:Name="TxtXray"    Text="Xray     : проверяю..." Foreground="#C6D0DA" FontFamily="Consolas" FontSize="12"/>
          <TextBlock x:Name="TxtConfig"  Text="Конфиг   : проверяю..." Foreground="#C6D0DA" FontFamily="Consolas" FontSize="12"/>
          <TextBlock x:Name="TxtSub"     Text="Подписка : проверяю..." Foreground="#C6D0DA" FontFamily="Consolas" FontSize="12"/>
        </StackPanel>
      </Border>

      <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,14,0,0">
        <TextBlock Text="Сервер:" Foreground="#8B98A5" VerticalAlignment="Center" Margin="0,0,8,0"/>
        <TextBox x:Name="TxtServer" Width="60" Background="#101821" Foreground="#E8EAED"
                 BorderBrush="#24303D" Padding="6,4" TextAlignment="Center"/>
        <TextBlock Text="параметры:" Foreground="#8B98A5" VerticalAlignment="Center" Margin="16,0,8,0"/>
        <TextBox x:Name="TxtExtra" Width="220" Background="#101821" Foreground="#E8EAED"
                 BorderBrush="#24303D" Padding="6,4"/>
      </StackPanel>

      <ScrollViewer Grid.Row="3" VerticalScrollBarVisibility="Auto" Margin="0,16,0,0">
        <StackPanel>
          <Button x:Name="BtnStart"  Style="{StaticResource MenuButton}" Content="▶  Запустить сессию"/>
          <Button x:Name="BtnCustom" Style="{StaticResource MenuButton}" Content="⚙  Запустить с настройками (сервер, -Fast)"/>
          <Button x:Name="BtnUpdate" Style="{StaticResource MenuButton}" Content="↻  Обновить подписку сейчас"/>
          <Button x:Name="BtnHome"   Style="{StaticResource MenuButton}" Content="⬇  Подготовка дома (браузер и Xray)"/>
          <Button x:Name="BtnBundle" Style="{StaticResource MenuButton}" Content="▤  Собрать полную сборку в zip"/>
          <Button x:Name="BtnClean"  Style="{StaticResource MenuButton}" Content="✕  Почистить следы (-Deep, -Scrub)"/>
          <Button x:Name="BtnCheck"  Style="{StaticResource MenuButton}" Content="✓  Проверка комплекта"/>
          <Button x:Name="BtnConsole" Style="{StaticResource MenuButton}" Content="▣  Открыть консольное меню"/>
        </StackPanel>
      </ScrollViewer>

      <Grid Grid.Row="4" Margin="0,10,0,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock x:Name="TxtStatus" Grid.Column="0" Text="Готов" Style="{StaticResource Caption}" VerticalAlignment="Center"/>
        <Button x:Name="BtnExit" Grid.Column="1" Content="Выход" Style="{StaticResource MenuButton}" Margin="0" Padding="20,8"/>
      </Grid>
    </Grid>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$Xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# --- доступ к элементам по имени
$names = @('CrossGroup','ScalesGroup','CrossScale','ScalesScale')
foreach ($n in $names) { Set-Variable -Name $n -Value $window.FindName($n) -Scope Script }
foreach ($n in @('ShroudTopSkew','ShroudLeftSkew','ShroudRightSkew','FoldLeftSkew','FoldRightSkew',
                 'CupLeftShift','CupRightShift','ChainLeft','ChainRight')) {
    Set-Variable -Name $n -Value $window.FindName($n) -Scope Script
}
foreach ($n in @('BtnStart','BtnCustom','BtnUpdate','BtnHome','BtnBundle','BtnClean','BtnCheck','BtnConsole','BtnExit',
                 'TxtServer','TxtExtra','TxtStatus','TxtBrowser','TxtXray','TxtConfig','TxtSub')) {
    Set-Variable -Name $n -Value $window.FindName($n) -Scope Script
}

# ---------------------------------------------------------------- анимации
function Add-SkewWave($transform, [double]$from, [double]$to, [double]$seconds, [double]$delay) {
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $anim.From = $from
    $anim.To = $to
    $anim.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds($seconds))
    $anim.AutoReverse = $true
    $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $anim.EasingFunction = New-Object System.Windows.Media.Animation.SineEase
    $anim.BeginTime = [TimeSpan]::FromSeconds($delay)
    $transform.BeginAnimation([System.Windows.Media.SkewTransform]::AngleXProperty, $anim)
}

function Add-ShiftWave($transform, [double]$amplitude, [double]$seconds, [double]$delay) {
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $anim.From = 0
    $anim.To = $amplitude
    $anim.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds($seconds))
    $anim.AutoReverse = $true
    $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $anim.EasingFunction = New-Object System.Windows.Media.Animation.SineEase
    $anim.BeginTime = [TimeSpan]::FromSeconds($delay)
    $transform.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
}

function Add-LineWave($line, [double]$from, [double]$to, [double]$seconds, [double]$delay) {
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $anim.From = $from
    $anim.To = $to
    $anim.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds($seconds))
    $anim.AutoReverse = $true
    $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $anim.EasingFunction = New-Object System.Windows.Media.Animation.SineEase
    $anim.BeginTime = [TimeSpan]::FromSeconds($delay)
    $line.BeginAnimation([System.Windows.Shapes.Line]::Y2Property, $anim)
}

# ткань: каждое полотнище качается со своей фазой
Add-SkewWave $ShroudTopSkew   -3.0  3.0  3.4  0.0
Add-SkewWave $ShroudLeftSkew  -5.0  5.0  2.9  0.4
Add-SkewWave $ShroudRightSkew  5.0 -5.0  3.2  0.9
Add-SkewWave $FoldLeftSkew    -4.0  4.0  2.9  0.4
Add-SkewWave $FoldRightSkew    4.0 -4.0  3.2  0.9

# чаши: противофаза
Add-ShiftWave $CupLeftShift   16.0 2.6 0.0
Add-ShiftWave $CupRightShift -16.0 2.6 0.6
Add-LineWave  $ChainLeft  196 212 2.6 0.0
Add-LineWave  $ChainRight 196 180 2.6 0.6

# ---------------------------------------------------------------- смена образа
$script:ShowCross = $true
$script:Switch = New-Object System.Windows.Threading.DispatcherTimer
$script:Switch.Interval = [TimeSpan]::FromSeconds(30)
$script:Switch.Add_Tick({
    $fadeOut = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fadeOut.From = 1.0; $fadeOut.To = 0.0
    $fadeOut.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds(0.7))
    $fadeIn = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fadeIn.From = 0.0; $fadeIn.To = 1.0
    $fadeIn.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds(0.7))
    $fadeIn.BeginTime = [TimeSpan]::FromSeconds(0.45)

    if ($script:ShowCross) {
        $ScalesGroup.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)
        $CrossGroup.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeOut)
    } else {
        $CrossGroup.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)
        $ScalesGroup.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeOut)
    }
    $script:ShowCross = -not $script:ShowCross
})
$script:Switch.Start()

# ---------------------------------------------------------------- статус
function Update-Status {
    if (Test-Path (Join-Path $App 'LibreWolf\LibreWolf.exe')) {
        $TxtBrowser.Text = 'Браузер  : установлен'
        $TxtBrowser.Foreground = '#8FE388'
    } else {
        $TxtBrowser.Text = 'Браузер  : НЕТ (пункт «Подготовка дома»)'
        $TxtBrowser.Foreground = '#FF8A80'
    }
    if (Test-Path (Join-Path $Vpn 'xray.exe')) {
        $TxtXray.Text = 'Xray     : установлен'
        $TxtXray.Foreground = '#8FE388'
    } else {
        $TxtXray.Text = 'Xray     : НЕТ (пункт «Подготовка дома»)'
        $TxtXray.Foreground = '#FF8A80'
    }
    if (Test-Path $Cfg) {
        $n = 0
        try { $n = @((Get-Content $Cfg -Raw -Encoding UTF8 | ConvertFrom-Json).outbounds).Count } catch {}
        $age = [int]((Get-Date) - (Get-Item $Cfg).LastWriteTime).TotalDays
        $TxtConfig.Text = ('Конфиг   : ' + $n + ' сервер(ов), возраст ' + $age + ' дн.')
        $TxtConfig.Foreground = '#8FE388'
    } else {
        $TxtConfig.Text = 'Конфиг   : нет'
        $TxtConfig.Foreground = '#FF8A80'
    }
    if ((Test-Path $SubFile) -and ((Get-Content $SubFile -Raw -ErrorAction SilentlyContinue) -match 'url\s*=\s*\S+')) {
        $TxtSub.Text = 'Подписка : настроена'
        $TxtSub.Foreground = '#8FE388'
    } else {
        $TxtSub.Text = 'Подписка : нет'
        $TxtSub.Foreground = '#FFD166'
    }
}
Update-Status

# ---------------------------------------------------------------- запуск действий
$script:Proc = $null

function Start-Tool([string]$Script, [string[]]$Extra = @()) {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $App $Script) + '"')) + $Extra
    try {
        $script:Proc = Start-Process -FilePath $ps -ArgumentList $a -PassThru
        $TxtStatus.Text = 'Открыто отдельное окно: ' + $Script
        $window.WindowState = 'Minimized'
    } catch {
        $TxtStatus.Text = 'Не удалось запустить: ' + $_.Exception.Message
    }
}

$watch = New-Object System.Windows.Threading.DispatcherTimer
$watch.Interval = [TimeSpan]::FromMilliseconds(700)
$watch.Add_Tick({
    if ($script:Proc -and $script:Proc.HasExited) {
        $script:Proc = $null
        $window.WindowState = 'Normal'
        Update-Status
        $TxtStatus.Text = 'Готово'
    }
})
$watch.Start()

$BtnStart.Add_Click({ Start-Tool 'start.ps1' })

$BtnCustom.Add_Click({
    $extra = @()
    if ($TxtServer.Text.Trim() -match '^\d+$') { $extra += @('-Server', $TxtServer.Text.Trim()) }
    if ($TxtExtra.Text.Trim() -ne '') { $extra += ($TxtExtra.Text.Trim() -split '\s+') }
    Start-Tool 'start.ps1' $extra
})

$BtnUpdate.Add_Click({ Start-Tool 'start.ps1' @('-ForceUpdate') })
$BtnHome.Add_Click({ Start-Tool 'prepare-home.ps1' })
$BtnBundle.Add_Click({ Start-Tool 'make-bundle.ps1' })
$BtnClean.Add_Click({ Start-Tool 'clean-traces.ps1' })
$BtnCheck.Add_Click({ Start-Tool 'self-check.ps1' })
$BtnConsole.Add_Click({
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $App 'menu.ps1') + '"'))
    try { $script:Proc = Start-Process -FilePath $ps -ArgumentList $a -PassThru; $window.WindowState = 'Minimized' } catch { }
})
$BtnExit.Add_Click({ $window.Close() })

$window.Add_Loaded({ $window.Activate() | Out-Null })
[void]$window.ShowDialog()
exit 0
