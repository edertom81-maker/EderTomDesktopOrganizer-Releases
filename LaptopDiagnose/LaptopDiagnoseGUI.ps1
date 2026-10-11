#Requires -Version 5.1
<#
.SYNOPSIS
    Grafische Oberfläche für PC Repair Pro.

.DESCRIPTION
    Fenster mit Navigation, Ergebniskarten, Verlauf, Rückgängig-Zentrale und Einstellungen. Alle Prüfungen und
    Reparaturen stammen aus LaptopDiagnose.ps1 (und dem Ordner Module) und laufen in einem Hintergrund-Runspace,
    damit das Fenster bedienbar bleibt. Änderungen am System erfolgen nur nach Auswahl und ausdrücklicher Bestätigung.

.PARAMETER NurPruefen
    Startet mit aktivem Schalter »Nur prüfen« (Reparaturen sind gesperrt).

.PARAMETER BerichtOrdner
    Zielordner für Berichte, Verlauf und Einstellungen (Standard: der in den Einstellungen gewählte Ordner,
    sonst der lokale Ordner Dokumente\LaptopDiagnose – bewusst nicht der nach OneDrive umgeleitete).

.NOTES
    Copyright 2026 by Eder Tom
#>
[CmdletBinding()]
param(
    [switch]$NurPruefen,
    [string]$BerichtOrdner
)

$Script:EnginePath = Join-Path $PSScriptRoot 'LaptopDiagnose.ps1'
$Script:IsAdmin = $false
try {
    $Script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }

# Mit Administratorrechten und im STA-Modus (für WPF erforderlich) neu starten
$isSta = [Threading.Thread]::CurrentThread.GetApartmentState() -eq [Threading.ApartmentState]::STA
if (-not $Script:IsAdmin -or -not $isSta) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Minimized', '-File', "`"$PSCommandPath`"")
    if ($BerichtOrdner) { $argList += @('-BerichtOrdner', "`"$BerichtOrdner`"") }
    if ($NurPruefen) { $argList += '-NurPruefen' }
    $exe = (Get-Process -Id $PID).Path
    try {
        if ($Script:IsAdmin) { Start-Process -FilePath $exe -ArgumentList $argList -WindowStyle Minimized }
        else { Start-Process -FilePath $exe -ArgumentList $argList -Verb RunAs -WindowStyle Minimized }
        return
    } catch {
        # Rechteabfrage abgelehnt: eingeschränkt weiterarbeiten (nur möglich, wenn bereits STA)
        if (-not $isSta) { return }
    }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# Berichtordner festlegen (beim ersten Start ab 2.4 einmalig aus dem OneDrive-Dokumente-Ordner umziehen)
. (Join-Path $PSScriptRoot 'Module\Berichtordner.ps1')
. (Join-Path $PSScriptRoot 'Module\Programm.ps1')
. (Join-Path $PSScriptRoot 'Module\LiveMonitor.ps1')
$Script:FolderMigrationMessage = $null
$folderInfo = Resolve-ReportFolder -Requested $BerichtOrdner
$BerichtOrdner = $folderInfo.Folder
$Script:FolderMigrationMessage = $folderInfo.Message

#region ---------- Farbpaletten (Hell / Dunkel) ----------

$Script:Palettes = @{
    Hell   = [ordered]@{
        BgWindow = '#F3F5F9'; BgCard = '#FFFFFF'; BgSidebar = '#13233A'; SidebarHover = '#1D3350'; SidebarActive = '#2A4B76'
        SidebarText = '#C3CFDF'; SidebarMuted = '#8EA2BD'; SidebarDivider = '#24395A'
        TextPrimary = '#1D2533'; TextHeading = '#13233A'; TextSecondary = '#5D6B80'; TextMuted = '#8A96A8'
        Border = '#E2E7EF'; ButtonBg = '#FFFFFF'; ButtonBorder = '#CBD3DF'; DetailBg = '#F6F8FB'; DetailText = '#2C3A4F'
        Link = '#0B5CAD'; FixText = '#0B4F8A'; BannerBg = '#FFF4E0'; BannerBorder = '#F5C26B'; BannerText = '#7A4A00'
        LogBg = '#0F1720'; LogText = '#D6DEE8'; Track = '#E9EEF5'; InputBg = '#FFFFFF'
    }
    Dunkel = [ordered]@{
        BgWindow = '#0F141B'; BgCard = '#18202B'; BgSidebar = '#0A111B'; SidebarHover = '#172537'; SidebarActive = '#22406A'
        SidebarText = '#C3CFDF'; SidebarMuted = '#8EA2BD'; SidebarDivider = '#1E2E44'
        TextPrimary = '#E6EBF2'; TextHeading = '#F1F5FA'; TextSecondary = '#A3B1C4'; TextMuted = '#7D8BA0'
        Border = '#2A3544'; ButtonBg = '#1F2935'; ButtonBorder = '#3A475A'; DetailBg = '#111821'; DetailText = '#C9D3E0'
        Link = '#5BA7EF'; FixText = '#7DB8F5'; BannerBg = '#3A2A0F'; BannerBorder = '#7A5A1F'; BannerText = '#F5D9A0'
        LogBg = '#0A0F15'; LogText = '#D6DEE8'; Track = '#243041'; InputBg = '#111821'
    }
}

function Get-PaletteXaml {
    ($Script:Palettes.Hell.Keys | ForEach-Object { "    <SolidColorBrush x:Key=""$_"" Color=""$($Script:Palettes.Hell[$_])""/>" }) -join "`n"
}

#endregion

#region ---------- Oberfläche (XAML) ----------

$Script:Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Repair Pro  ·  © 2026 Eder Tom" Width="1240" Height="840" MinWidth="1020" MinHeight="640"
        WindowStartupLocation="CenterScreen" WindowState="Maximized" Background="{DynamicResource BgWindow}" FontFamily="Segoe UI" FontSize="13"
        TextOptions.TextFormattingMode="Display" UseLayoutRounding="True">
  <Window.Resources>
%PALETTE%
    <BooleanToVisibilityConverter x:Key="B2V"/>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Background" Value="{DynamicResource ButtonBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource ButtonBorder}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="Margin" Value="8,0,0,0"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.7"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="BtnPrimary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#0B5CAD"/>
      <Setter Property="BorderBrush" Value="#0B5CAD"/>
      <Setter Property="Foreground" Value="White"/>
    </Style>
    <Style x:Key="BtnSuccess" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#067A46"/>
      <Setter Property="BorderBrush" Value="#067A46"/>
      <Setter Property="Foreground" Value="White"/>
    </Style>

    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{DynamicResource SidebarText}"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Margin" Value="0,1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="GroupName" Value="Nav"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" Background="Transparent" CornerRadius="8" Padding="12,8">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource SidebarHover}"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="{DynamicResource SidebarActive}"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Seg" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="Margin" Value="0,0,6,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" Background="{DynamicResource ButtonBg}" BorderBrush="{DynamicResource ButtonBorder}" BorderThickness="1" CornerRadius="7" Padding="12,6">
              <ContentPresenter HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="#0B5CAD"/>
                <Setter TargetName="b" Property="BorderBrush" Value="#0B5CAD"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="NavIcon" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="Width" Value="28"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="Badge" TargetType="Border">
      <Setter Property="Background" Value="#D92D20"/>
      <Setter Property="CornerRadius" Value="9"/>
      <Setter Property="Padding" Value="7,1"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Visibility" Value="Collapsed"/>
    </Style>
    <Style x:Key="BadgeText" TargetType="TextBlock">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource BgCard}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Border}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="18,14"/>
      <Setter Property="Margin" Value="0,0,0,12"/>
    </Style>
    <Style x:Key="CardTitle" TargetType="TextBlock">
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="{DynamicResource TextHeading}"/>
      <Setter Property="Margin" Value="0,0,0,6"/>
    </Style>
    <Style x:Key="Muted" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
    <Style x:Key="Tile" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource BgCard}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Border}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="14,10"/>
      <Setter Property="Margin" Value="0,0,12,0"/>
    </Style>
    <Style x:Key="TileNumber" TargetType="TextBlock">
      <Setter Property="FontSize" Value="30"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="HorizontalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="TileLabel" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
      <Setter Property="HorizontalAlignment" Value="Center"/>
    </Style>

    <DataTemplate x:Key="FindingTemplate">
      <Border Background="{DynamicResource BgCard}" CornerRadius="10" Margin="0,0,0,10" BorderBrush="{DynamicResource Border}" BorderThickness="1">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="6"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Border x:Name="Bar" CornerRadius="10,0,0,10" Background="#079455"/>
          <StackPanel Grid.Column="1" Margin="16,12,16,12">
            <DockPanel LastChildFill="True">
              <Border x:Name="SevBadge" DockPanel.Dock="Left" CornerRadius="9" Padding="9,2" Background="#079455" VerticalAlignment="Top" Margin="0,1,10,0">
                <TextBlock Text="{Binding Severity}" Foreground="White" FontSize="11" FontWeight="SemiBold"/>
              </Border>
              <Button DockPanel.Dock="Right" Tag="HideBtn" Content="Ausblenden" ToolTip="Diese Meldung bei künftigen Prüfungen nicht mehr anzeigen (wieder einblenden unter Einstellungen)"
                      Visibility="{Binding CanHide, Converter={StaticResource B2V}}" Cursor="Hand" Margin="10,0,0,0" Padding="6,1" FontSize="11"
                      Background="Transparent" BorderThickness="0" Foreground="{DynamicResource Link}" VerticalAlignment="Top"/>
              <Border DockPanel.Dock="Right" Width="18" Height="18" CornerRadius="9" BorderThickness="1" BorderBrush="{DynamicResource TextMuted}" Margin="8,1,0,0" VerticalAlignment="Top"
                      Visibility="{Binding HasHelp, Converter={StaticResource B2V}}" Cursor="Help" Background="Transparent" ToolTipService.ShowDuration="60000" ToolTipService.InitialShowDelay="150">
                <Border.ToolTip>
                  <ToolTip MaxWidth="420">
                    <StackPanel>
                      <TextBlock Text="{Binding CheckName}" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,0,0,4"/>
                      <TextBlock Text="{Binding Help}" TextWrapping="Wrap"/>
                    </StackPanel>
                  </ToolTip>
                </Border.ToolTip>
                <TextBlock Text="?" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource TextMuted}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <TextBlock DockPanel.Dock="Right" Text="{Binding CategoryTitle}" Foreground="{DynamicResource TextMuted}" FontSize="11" Margin="10,3,0,0"/>
              <TextBlock Text="{Binding Title}" FontWeight="SemiBold" FontSize="14" Foreground="{DynamicResource TextPrimary}" TextWrapping="Wrap"/>
            </DockPanel>
            <TextBlock Text="{Binding Detail}" Visibility="{Binding HasDetail, Converter={StaticResource B2V}}"
                       Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,6,0,0"/>
            <ItemsControl ItemsSource="{Binding Chart}" Visibility="{Binding HasChart, Converter={StaticResource B2V}}" Margin="0,10,0,0">
              <ItemsControl.ItemTemplate>
                <DataTemplate>
                  <Grid Margin="0,2">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="220"/>
                      <ColumnDefinition Width="310"/>
                      <ColumnDefinition Width="90"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Text="{Binding Label}" Foreground="{DynamicResource TextPrimary}" FontSize="12" TextTrimming="CharacterEllipsis"/>
                    <Border Grid.Column="1" Background="{DynamicResource Track}" CornerRadius="5" Height="10" VerticalAlignment="Center">
                      <Border Background="#1570EF" CornerRadius="5" HorizontalAlignment="Left" Width="{Binding BarWidth}"/>
                    </Border>
                    <TextBlock Grid.Column="2" Text="{Binding Text}" Foreground="{DynamicResource TextSecondary}" FontSize="12" HorizontalAlignment="Right"/>
                  </Grid>
                </DataTemplate>
              </ItemsControl.ItemTemplate>
            </ItemsControl>
            <ItemsControl ItemsSource="{Binding Tiles}" Visibility="{Binding HasTiles, Converter={StaticResource B2V}}" Margin="0,10,0,0"
                          Width="700" Height="280" HorizontalAlignment="Left" ClipToBounds="True">
              <ItemsControl.ItemsPanel>
                <ItemsPanelTemplate><Canvas/></ItemsPanelTemplate>
              </ItemsControl.ItemsPanel>
              <ItemsControl.ItemContainerStyle>
                <Style TargetType="ContentPresenter">
                  <Setter Property="Canvas.Left" Value="{Binding X}"/>
                  <Setter Property="Canvas.Top" Value="{Binding Y}"/>
                </Style>
              </ItemsControl.ItemContainerStyle>
              <ItemsControl.ItemTemplate>
                <DataTemplate>
                  <Border Width="{Binding W}" Height="{Binding H}" Background="{Binding Fill}" BorderBrush="{DynamicResource BgCard}" BorderThickness="1" ToolTip="{Binding Tip}" Cursor="{Binding Cursor}" Tag="TreemapTile">
                    <StackPanel Margin="6,4,4,2" Visibility="{Binding ShowText, Converter={StaticResource B2V}}">
                      <TextBlock Text="{Binding Label}" Foreground="White" FontWeight="SemiBold" FontSize="12" TextTrimming="CharacterEllipsis"/>
                      <TextBlock Text="{Binding Text}" Foreground="White" FontSize="11" Opacity="0.85"/>
                    </StackPanel>
                  </Border>
                </DataTemplate>
              </ItemsControl.ItemTemplate>
            </ItemsControl>
            <Expander Header="Details anzeigen" Visibility="{Binding HasItems, Converter={StaticResource B2V}}" Margin="0,6,0,0" Foreground="{DynamicResource Link}">
              <StackPanel>
                <TextBlock Text="Doppelklick auf eine Zeile mit Pfad öffnet den Ordner im Explorer." Visibility="{Binding HasPaths, Converter={StaticResource B2V}}"
                           Foreground="{DynamicResource TextMuted}" FontSize="11" Margin="2,6,0,0"/>
                <TextBox Tag="DetailBox" Text="{Binding ItemsText, Mode=OneWay}" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                         BorderThickness="0" Background="{DynamicResource DetailBg}" Foreground="{DynamicResource DetailText}" TextWrapping="Wrap" Padding="10,8" Margin="0,6,0,0"/>
              </StackPanel>
            </Expander>
            <CheckBox IsChecked="{Binding IsSelected, Mode=TwoWay}" Visibility="{Binding ShowFix, Converter={StaticResource B2V}}"
                      Margin="0,10,0,0" Cursor="Hand" VerticalContentAlignment="Center">
              <TextBlock Text="{Binding FixText}" Foreground="{DynamicResource FixText}" FontWeight="SemiBold" TextWrapping="Wrap"/>
            </CheckBox>
            <TextBlock x:Name="StatusText" Text="{Binding Status}" Visibility="{Binding HasStatus, Converter={StaticResource B2V}}"
                       Foreground="#D92D20" TextWrapping="Wrap" Margin="0,10,0,0" FontWeight="SemiBold"/>
          </StackPanel>
        </Grid>
      </Border>
      <DataTemplate.Triggers>
        <DataTrigger Binding="{Binding Severity}" Value="Kritisch">
          <Setter TargetName="Bar" Property="Background" Value="#D92D20"/>
          <Setter TargetName="SevBadge" Property="Background" Value="#D92D20"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding Severity}" Value="Warnung">
          <Setter TargetName="Bar" Property="Background" Value="#DC8A00"/>
          <Setter TargetName="SevBadge" Property="Background" Value="#DC8A00"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding Severity}" Value="Info">
          <Setter TargetName="Bar" Property="Background" Value="#1570EF"/>
          <Setter TargetName="SevBadge" Property="Background" Value="#1570EF"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding IsFixed}" Value="True">
          <Setter TargetName="StatusText" Property="Foreground" Value="#079455"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding RunOk}" Value="True">
          <Setter TargetName="StatusText" Property="Foreground" Value="#079455"/>
        </DataTrigger>
      </DataTemplate.Triggers>
    </DataTemplate>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="256"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- Seitenleiste -->
    <Border Background="{DynamicResource BgSidebar}">
      <DockPanel>
        <StackPanel DockPanel.Dock="Top" Margin="22,24,22,14">
          <StackPanel Orientation="Horizontal">
            <Image x:Name="SidebarLogo" Width="44" Height="44" Margin="0,0,12,0" VerticalAlignment="Center" RenderOptions.BitmapScalingMode="HighQuality"/>
            <TextBlock FontSize="19" FontWeight="Black" VerticalAlignment="Center">
              <Run Text="PC REPAIR " Foreground="White"/><Run Text="PRO" Foreground="#2E9BFF"/>
            </TextBlock>
          </StackPanel>
          <!-- Slogan über die volle Breite; bricht bei Platzmangel um, statt abgeschnitten zu werden -->
          <TextBlock Text="Diagnose • Repair • Keep it running" FontSize="12" Foreground="{DynamicResource SidebarText}" TextWrapping="Wrap" Margin="2,10,0,0"/>
          <TextBlock x:Name="VersionText" Text="" FontSize="11" Foreground="{DynamicResource SidebarMuted}" Margin="2,2,0,0"/>
        </StackPanel>

        <StackPanel DockPanel.Dock="Bottom" Margin="20,8,20,18">
          <CheckBox x:Name="ChkNurPruefen" Cursor="Hand" Margin="0,0,0,12">
            <TextBlock Text="Nur prüfen (keine Änderungen)" TextWrapping="Wrap" Foreground="{DynamicResource SidebarText}"/>
          </CheckBox>
          <Button x:Name="BtnReport" Style="{StaticResource Btn}" Margin="0" Background="{DynamicResource SidebarHover}" Foreground="White" BorderBrush="{DynamicResource SidebarActive}">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE8A5;" FontFamily="Segoe MDL2 Assets" Margin="0,0,8,0" VerticalAlignment="Center"/>
              <TextBlock Text="Bericht speichern &amp; öffnen"/>
            </StackPanel>
          </Button>
          <Button x:Name="BtnFolder" Style="{StaticResource Btn}" Margin="0,8,0,0" Background="Transparent" Foreground="{DynamicResource SidebarMuted}" BorderBrush="Transparent" Padding="4">
            <TextBlock Text="Berichtsordner öffnen" TextDecorations="Underline"/>
          </Button>
          <TextBlock Text="© 2026 Eder Tom" Foreground="{DynamicResource SidebarMuted}" FontSize="11" Margin="4,12,0,0"/>
        </StackPanel>

        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <StackPanel Margin="12,0">
            <RadioButton x:Name="NavAlle" Tag="Alle" Style="{StaticResource Nav}" IsChecked="True">
              <DockPanel><TextBlock Text="&#xE80F;" Style="{StaticResource NavIcon}"/><TextBlock Text="Übersicht" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavFehler" Tag="Fehler" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE7BA;" Style="{StaticResource NavIcon}"/>
                <Border x:Name="BadgeFehler" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeFehlerText" Style="{StaticResource BadgeText}"/></Border>
                <TextBlock Text="Fehlersuche" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavSicherheit" Tag="Sicherheit" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE72E;" Style="{StaticResource NavIcon}"/>
                <Border x:Name="BadgeSicherheit" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeSicherheitText" Style="{StaticResource BadgeText}"/></Border>
                <TextBlock Text="Sicherheit" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavSpeicher" Tag="Speicher" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xEDA2;" Style="{StaticResource NavIcon}"/>
                <Border x:Name="BadgeSpeicher" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeSpeicherText" Style="{StaticResource BadgeText}"/></Border>
                <TextBlock Text="Speicherfresser" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavLeistung" Tag="Leistung" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE945;" Style="{StaticResource NavIcon}"/>
                <Border x:Name="BadgeLeistung" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeLeistungText" Style="{StaticResource BadgeText}"/></Border>
                <TextBlock Text="Leistungsbremsen" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavHerunterfahren" Tag="Herunterfahren" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE7E8;" Style="{StaticResource NavIcon}"/>
                <Border x:Name="BadgeHerunterfahren" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeHerunterfahrenText" Style="{StaticResource BadgeText}"/></Border>
                <TextBlock Text="Herunterfahren" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavAkku" Tag="Akku" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE83F;" Style="{StaticResource NavIcon}"/>
                <Border x:Name="BadgeAkku" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeAkkuText" Style="{StaticResource BadgeText}"/></Border>
                <TextBlock Text="Akku" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavNetzwerk" Tag="Netzwerk" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE701;" Style="{StaticResource NavIcon}"/>
                <Border x:Name="BadgeNetzwerk" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeNetzwerkText" Style="{StaticResource BadgeText}"/></Border>
                <TextBlock Text="Netzwerk &amp; WLAN" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavSoftware" Tag="Software" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE896;" Style="{StaticResource NavIcon}"/>
                <Border x:Name="BadgeSoftware" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeSoftwareText" Style="{StaticResource BadgeText}"/></Border>
                <TextBlock Text="Software-Updates" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavWindows" Tag="Windows" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE895;" Style="{StaticResource NavIcon}"/>
                <Border x:Name="BadgeWindows" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeWindowsText" Style="{StaticResource BadgeText}"/></Border>
                <TextBlock Text="Windows &amp; Treiber" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavWerkzeuge" Tag="Werkzeuge" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE90F;" Style="{StaticResource NavIcon}"/>
                <Border x:Name="BadgeWerkzeuge" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeWerkzeugeText" Style="{StaticResource BadgeText}"/></Border>
                <TextBlock Text="Reparatur-Werkzeuge" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <Border Height="1" Background="{DynamicResource SidebarDivider}" Margin="8,8"/>
            <RadioButton x:Name="NavMonitor" Tag="Monitor" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE7F4;" Style="{StaticResource NavIcon}"/><TextBlock Text="Live-Monitor" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavVerlauf" Tag="Verlauf" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE81C;" Style="{StaticResource NavIcon}"/><TextBlock Text="Verlauf &amp; Trends" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavAenderungen" Tag="Aenderungen" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE7A7;" Style="{StaticResource NavIcon}"/><TextBlock Text="Änderungen" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavEinstellungen" Tag="Einstellungen" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE713;" Style="{StaticResource NavIcon}"/>
                <Border x:Name="BadgeUpdate" DockPanel.Dock="Right" Style="{StaticResource Badge}" Background="#067A46"><TextBlock Text="Update" Style="{StaticResource BadgeText}"/></Border>
                <TextBlock Text="Einstellungen" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
            <RadioButton x:Name="NavLog" Tag="Log" Style="{StaticResource Nav}">
              <DockPanel><TextBlock Text="&#xE9D9;" Style="{StaticResource NavIcon}"/><TextBlock Text="Protokoll" VerticalAlignment="Center"/></DockPanel>
            </RadioButton>
          </StackPanel>
        </ScrollViewer>
      </DockPanel>
    </Border>

    <!-- Hauptbereich -->
    <Grid Grid.Column="1" Margin="28,22,28,18">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Border x:Name="AdminBanner" Background="{DynamicResource BannerBg}" BorderBrush="{DynamicResource BannerBorder}" BorderThickness="1" CornerRadius="8" Padding="12,8" Margin="0,0,0,14" Visibility="Collapsed">
        <TextBlock TextWrapping="Wrap" Foreground="{DynamicResource BannerText}" Text="Ohne Administratorrechte gestartet: Einige Prüfungen liefern weniger Ergebnisse, und Reparaturen sowie Updates können fehlschlagen. Für den vollen Funktionsumfang das Programm neu starten und die Rechteabfrage bestätigen."/>
      </Border>

      <DockPanel Grid.Row="1" Margin="0,0,0,16">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="BtnScanPage" Style="{StaticResource Btn}">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" Margin="0,0,8,0" VerticalAlignment="Center"/>
              <TextBlock x:Name="BtnScanPageText" Text="Diesen Bereich prüfen"/>
            </StackPanel>
          </Button>
          <Button x:Name="BtnFullScan" Style="{StaticResource BtnPrimary}">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE768;" FontFamily="Segoe MDL2 Assets" Margin="0,0,8,0" VerticalAlignment="Center"/>
              <TextBlock Text="Komplett-Diagnose starten"/>
            </StackPanel>
          </Button>
        </StackPanel>
        <StackPanel>
          <TextBlock x:Name="PageTitle" Text="Übersicht" FontSize="24" FontWeight="Bold" Foreground="{DynamicResource TextHeading}"/>
          <TextBlock x:Name="PageSubtitle" Text="" Foreground="{DynamicResource TextSecondary}" Margin="0,2,0,0" TextWrapping="Wrap"/>
        </StackPanel>
      </DockPanel>

      <Grid x:Name="Tiles" Grid.Row="2" Margin="0,0,-12,16">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="1.3*"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Border Style="{StaticResource Tile}">
          <StackPanel>
            <TextBlock x:Name="ScoreText" Text="–" Style="{StaticResource TileNumber}" Foreground="{DynamicResource TextMuted}"/>
            <TextBlock Text="Gesundheitswert" Style="{StaticResource TileLabel}"/>
          </StackPanel>
        </Border>
        <Border Grid.Column="1" Style="{StaticResource Tile}">
          <StackPanel><TextBlock x:Name="CountKritisch" Text="0" Style="{StaticResource TileNumber}" Foreground="#D92D20"/><TextBlock Text="Kritisch" Style="{StaticResource TileLabel}"/></StackPanel>
        </Border>
        <Border Grid.Column="2" Style="{StaticResource Tile}">
          <StackPanel><TextBlock x:Name="CountWarnung" Text="0" Style="{StaticResource TileNumber}" Foreground="#DC8A00"/><TextBlock Text="Warnungen" Style="{StaticResource TileLabel}"/></StackPanel>
        </Border>
        <Border Grid.Column="3" Style="{StaticResource Tile}">
          <StackPanel><TextBlock x:Name="CountInfo" Text="0" Style="{StaticResource TileNumber}" Foreground="#1570EF"/><TextBlock Text="Hinweise" Style="{StaticResource TileLabel}"/></StackPanel>
        </Border>
        <Border Grid.Column="4" Style="{StaticResource Tile}">
          <StackPanel><TextBlock x:Name="CountOK" Text="0" Style="{StaticResource TileNumber}" Foreground="#079455"/><TextBlock Text="In Ordnung" Style="{StaticResource TileLabel}"/></StackPanel>
        </Border>
      </Grid>

      <Grid Grid.Row="3">
        <!-- Ergebnisse -->
        <ScrollViewer x:Name="FindingsScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <StackPanel Margin="0,0,6,0">
            <Border x:Name="SystemCard" Style="{StaticResource Card}" Margin="0,0,0,14" Visibility="Collapsed">
              <StackPanel>
                <TextBlock Text="Systemübersicht" Style="{StaticResource CardTitle}"/>
                <ItemsControl x:Name="SystemList">
                  <ItemsControl.ItemsPanel>
                    <ItemsPanelTemplate><UniformGrid Columns="2"/></ItemsPanelTemplate>
                  </ItemsControl.ItemsPanel>
                  <ItemsControl.ItemTemplate>
                    <DataTemplate>
                      <DockPanel Margin="0,3,16,3">
                        <TextBlock Text="{Binding Key}" Foreground="{DynamicResource TextSecondary}" Width="150"/>
                        <TextBlock Text="{Binding Value}" Foreground="{DynamicResource TextPrimary}" TextWrapping="Wrap"/>
                      </DockPanel>
                    </DataTemplate>
                  </ItemsControl.ItemTemplate>
                </ItemsControl>
              </StackPanel>
            </Border>
            <Border x:Name="EmptyHint" Style="{StaticResource Card}" Padding="24" Visibility="Collapsed">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="34" Foreground="{DynamicResource TextMuted}" HorizontalAlignment="Center"/>
                <TextBlock x:Name="EmptyHintText" Margin="0,10,0,0" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" TextAlignment="Center" FontSize="14"/>
              </StackPanel>
            </Border>
            <Border x:Name="FilterBar" Style="{StaticResource Card}" Padding="12,8" Margin="0,0,0,12">
              <DockPanel LastChildFill="True">
                <Button x:Name="BtnExportCsv" DockPanel.Dock="Right" Style="{StaticResource Btn}" Margin="10,0,0,0" ToolTip="Die angezeigten Ergebnisse als CSV-Datei (z. B. für Excel) im Berichtordner speichern">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock Text="&#xE9F9;" FontFamily="Segoe MDL2 Assets" Margin="0,0,8,0" VerticalAlignment="Center"/>
                    <TextBlock Text="Als CSV exportieren"/>
                  </StackPanel>
                </Button>
                <CheckBox x:Name="ChkOnlyFixable" DockPanel.Dock="Right" Content="Nur behebbare" VerticalAlignment="Center" Margin="12,0,0,0" Foreground="{DynamicResource TextPrimary}"/>
                <ComboBox x:Name="FilterSeverity" DockPanel.Dock="Right" Width="170" Margin="12,0,0,0" VerticalAlignment="Center" SelectedIndex="0">
                  <ComboBoxItem Content="Alle Schweregrade" Tag=""/>
                  <ComboBoxItem Content="Kritisch" Tag="Kritisch"/>
                  <ComboBoxItem Content="Warnungen" Tag="Warnung"/>
                  <ComboBoxItem Content="Hinweise" Tag="Info"/>
                  <ComboBoxItem Content="In Ordnung" Tag="OK"/>
                  <ComboBoxItem Content="Kritisch und Warnungen" Tag="Kritisch,Warnung"/>
                </ComboBox>
                <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" DockPanel.Dock="Left" VerticalAlignment="Center" Margin="2,0,8,0" Foreground="{DynamicResource TextMuted}"/>
                <Grid>
                  <TextBox x:Name="SearchBox" VerticalContentAlignment="Center" Padding="4,3" ToolTip="Sucht in Titel, Details, Einträgen und Prüfungsname"/>
                  <TextBlock x:Name="SearchHint" Text="Ergebnisse durchsuchen …" IsHitTestVisible="False" Foreground="{DynamicResource TextMuted}" Margin="8,0,0,0" VerticalAlignment="Center"/>
                </Grid>
              </DockPanel>
            </Border>
            <ItemsControl x:Name="FindingsList" ItemTemplate="{StaticResource FindingTemplate}"/>
          </StackPanel>
        </ScrollViewer>

        <!-- Verlauf -->
        <ScrollViewer x:Name="HistoryPanel" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <TextBlock x:Name="HistoryHint" Style="{StaticResource Muted}" Text="Nach jeder Komplett-Diagnose wird ein Messpunkt gespeichert. Ab zwei Messungen werden Trends sichtbar."/>
            </Border>
            <ItemsControl x:Name="HistoryList">
              <ItemsControl.ItemsPanel>
                <ItemsPanelTemplate><WrapPanel/></ItemsPanelTemplate>
              </ItemsControl.ItemsPanel>
              <ItemsControl.ItemTemplate>
                <DataTemplate>
                  <Border Width="306" Margin="0,0,12,12" Background="{DynamicResource BgCard}" BorderBrush="{DynamicResource Border}" BorderThickness="1" CornerRadius="12" Padding="16,12">
                    <StackPanel>
                      <TextBlock Text="{Binding Label}" Foreground="{DynamicResource TextSecondary}" TextTrimming="CharacterEllipsis"/>
                      <TextBlock Text="{Binding ValueText}" FontSize="24" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}"/>
                      <Canvas Width="272" Height="56" Margin="0,6,0,4" HorizontalAlignment="Left">
                        <Polyline Points="{Binding Points}" Stroke="{Binding Stroke}" StrokeThickness="2" StrokeLineJoin="Round"/>
                      </Canvas>
                      <TextBlock x:Name="TrendText" Text="{Binding TrendText}" Foreground="{DynamicResource TextSecondary}" FontSize="12" FontWeight="SemiBold"/>
                      <TextBlock Text="{Binding RangeText}" Foreground="{DynamicResource TextMuted}" FontSize="11" Margin="0,2,0,0"/>
                    </StackPanel>
                  </Border>
                  <DataTemplate.Triggers>
                    <DataTrigger Binding="{Binding Trend}" Value="besser"><Setter TargetName="TrendText" Property="Foreground" Value="#079455"/></DataTrigger>
                    <DataTrigger Binding="{Binding Trend}" Value="schlechter"><Setter TargetName="TrendText" Property="Foreground" Value="#DC8A00"/></DataTrigger>
                  </DataTemplate.Triggers>
                </DataTemplate>
              </ItemsControl.ItemTemplate>
            </ItemsControl>
          </StackPanel>
        </ScrollViewer>

        <!-- Live-Monitor -->
        <ScrollViewer x:Name="MonitorPanel" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <StackPanel Margin="0,0,6,0">
            <WrapPanel Margin="0,0,-12,0">
              <Border Style="{StaticResource Card}" Width="250" Margin="0,0,12,12">
                <StackPanel>
                  <TextBlock Text="Prozessor" Foreground="{DynamicResource TextSecondary}"/>
                  <TextBlock x:Name="MonCpu" Text="–" FontSize="26" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}"/>
                  <TextBlock x:Name="MonCpuSub" Text=" " Foreground="{DynamicResource TextMuted}" FontSize="12"/>
                  <Canvas Width="216" Height="48" Margin="0,6,0,0" HorizontalAlignment="Left" ClipToBounds="True">
                    <Polyline x:Name="MonCpuLine" Stroke="#1570EF" StrokeThickness="2" StrokeLineJoin="Round"/>
                  </Canvas>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}" Width="250" Margin="0,0,12,12">
                <StackPanel>
                  <TextBlock Text="Arbeitsspeicher" Foreground="{DynamicResource TextSecondary}"/>
                  <TextBlock x:Name="MonRam" Text="–" FontSize="26" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}"/>
                  <TextBlock x:Name="MonRamSub" Text=" " Foreground="{DynamicResource TextMuted}" FontSize="12"/>
                  <Canvas Width="216" Height="48" Margin="0,6,0,0" HorizontalAlignment="Left" ClipToBounds="True">
                    <Polyline x:Name="MonRamLine" Stroke="#7A5AF8" StrokeThickness="2" StrokeLineJoin="Round"/>
                  </Canvas>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}" Width="250" Margin="0,0,12,12">
                <StackPanel>
                  <TextBlock Text="Datenträger (aktiv)" Foreground="{DynamicResource TextSecondary}"/>
                  <TextBlock x:Name="MonDisk" Text="–" FontSize="26" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}"/>
                  <TextBlock x:Name="MonDiskSub" Text=" " Foreground="{DynamicResource TextMuted}" FontSize="12"/>
                  <Canvas Width="216" Height="48" Margin="0,6,0,0" HorizontalAlignment="Left" ClipToBounds="True">
                    <Polyline x:Name="MonDiskLine" Stroke="#DC8A00" StrokeThickness="2" StrokeLineJoin="Round"/>
                  </Canvas>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}" Width="250" Margin="0,0,12,12">
                <StackPanel>
                  <TextBlock Text="Netzwerk" Foreground="{DynamicResource TextSecondary}"/>
                  <TextBlock x:Name="MonNet" Text="–" FontSize="26" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}"/>
                  <TextBlock x:Name="MonNetSub" Text=" " Foreground="{DynamicResource TextMuted}" FontSize="12"/>
                  <Canvas Width="216" Height="48" Margin="0,6,0,0" HorizontalAlignment="Left" ClipToBounds="True">
                    <Polyline x:Name="MonNetLine" Stroke="#079455" StrokeThickness="2" StrokeLineJoin="Round"/>
                  </Canvas>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}" Width="250" Margin="0,0,12,12">
                <StackPanel>
                  <TextBlock Text="Temperatur" Foreground="{DynamicResource TextSecondary}"/>
                  <TextBlock x:Name="MonTemp" Text="–" FontSize="26" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}"/>
                  <TextBlock x:Name="MonTempSub" Text=" " Foreground="{DynamicResource TextMuted}" FontSize="12"/>
                  <Canvas Width="216" Height="48" Margin="0,6,0,0" HorizontalAlignment="Left" ClipToBounds="True">
                    <Polyline x:Name="MonTempLine" Stroke="#D92D20" StrokeThickness="2" StrokeLineJoin="Round"/>
                  </Canvas>
                </StackPanel>
              </Border>
            </WrapPanel>
            <Border Style="{StaticResource Card}" Margin="0,0,0,12">
              <StackPanel>
                <DockPanel>
                  <Button x:Name="BtnMonRecord" DockPanel.Dock="Right" Style="{StaticResource BtnPrimary}" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="&#xE7C8;" FontFamily="Segoe MDL2 Assets" Margin="0,0,8,0" VerticalAlignment="Center"/>
                      <TextBlock x:Name="BtnMonRecordText" Text="60 Sekunden aufzeichnen"/>
                    </StackPanel>
                  </Button>
                  <StackPanel>
                    <TextBlock Text="Was bremst gerade?" Style="{StaticResource CardTitle}"/>
                    <TextBlock x:Name="MonRecStatus" Style="{StaticResource Muted}" Text="Starten Sie die Aufzeichnung, während das Gerät langsam ist. Danach nennt PC Repair Pro die wahrscheinliche Ursache und die größten Verbraucher."/>
                  </StackPanel>
                </DockPanel>
                <TextBlock x:Name="MonRecVerdict" Visibility="Collapsed" TextWrapping="Wrap" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}" Margin="0,12,0,0"/>
                <TextBox x:Name="MonRecDetail" Visibility="Collapsed" IsReadOnly="True" FontFamily="Consolas" FontSize="12" BorderThickness="0" Background="Transparent" Foreground="{DynamicResource TextSecondary}" Margin="0,8,0,0"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Größte Verbraucher (laufend)" Style="{StaticResource CardTitle}"/>
                <Grid Margin="0,4,0,6">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="200"/><ColumnDefinition Width="110"/></Grid.ColumnDefinitions>
                  <TextBlock Text="Programm" Foreground="{DynamicResource TextMuted}" FontSize="12"/>
                  <TextBlock Grid.Column="1" Text="Prozessor" Foreground="{DynamicResource TextMuted}" FontSize="12"/>
                  <TextBlock Grid.Column="2" Text="Arbeitsspeicher" Foreground="{DynamicResource TextMuted}" FontSize="12" HorizontalAlignment="Right"/>
                </Grid>
                <ItemsControl x:Name="MonProcList">
                  <ItemsControl.ItemTemplate>
                    <DataTemplate>
                      <Grid Margin="0,3">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="200"/><ColumnDefinition Width="110"/></Grid.ColumnDefinitions>
                        <TextBlock Text="{Binding Name}" Foreground="{DynamicResource TextPrimary}" TextTrimming="CharacterEllipsis"/>
                        <StackPanel Grid.Column="1" Orientation="Horizontal">
                          <Border Width="{Binding BarW}" Height="10" CornerRadius="3" Background="#1570EF" VerticalAlignment="Center" Margin="0,0,8,0"/>
                          <TextBlock Text="{Binding CpuText}" Foreground="{DynamicResource TextSecondary}"/>
                        </StackPanel>
                        <TextBlock Grid.Column="2" Text="{Binding RamText}" Foreground="{DynamicResource TextSecondary}" HorizontalAlignment="Right"/>
                      </Grid>
                    </DataTemplate>
                  </ItemsControl.ItemTemplate>
                </ItemsControl>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>

        <!-- Änderungen -->
        <ScrollViewer x:Name="ChangesPanel" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <TextBlock x:Name="ChangesHint" Style="{StaticResource Muted}" Text="Hier steht jede Änderung, die PC Repair Pro vorgenommen hat. Umkehrbare Änderungen lassen sich einzeln zurücknehmen."/>
            </Border>
            <ItemsControl x:Name="ChangesList">
              <ItemsControl.ItemTemplate>
                <DataTemplate>
                  <Border Background="{DynamicResource BgCard}" BorderBrush="{DynamicResource Border}" BorderThickness="1" CornerRadius="10" Padding="16,12" Margin="0,0,0,10">
                    <DockPanel>
                      <Button DockPanel.Dock="Right" Style="{StaticResource Btn}" Tag="{Binding Id}" VerticalAlignment="Center"
                              Visibility="{Binding CanUndo, Converter={StaticResource B2V}}">
                        <StackPanel Orientation="Horizontal">
                          <TextBlock Text="&#xE7A7;" FontFamily="Segoe MDL2 Assets" Margin="0,0,8,0" VerticalAlignment="Center"/>
                          <TextBlock Text="Rückgängig"/>
                        </StackPanel>
                      </Button>
                      <StackPanel>
                        <TextBlock Text="{Binding Beschreibung}" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}" TextWrapping="Wrap"/>
                        <TextBlock x:Name="Meta" Text="{Binding Meta}" Foreground="{DynamicResource TextSecondary}" FontSize="12" Margin="0,3,0,0"/>
                        <TextBlock Text="{Binding Note}" Visibility="{Binding HasNote, Converter={StaticResource B2V}}" Foreground="{DynamicResource TextMuted}" FontSize="12" TextWrapping="Wrap" Margin="0,3,0,0"/>
                      </StackPanel>
                    </DockPanel>
                  </Border>
                  <DataTemplate.Triggers>
                    <DataTrigger Binding="{Binding Undone}" Value="True"><Setter TargetName="Meta" Property="Foreground" Value="#DC8A00"/></DataTrigger>
                  </DataTemplate.Triggers>
                </DataTemplate>
              </ItemsControl.ItemTemplate>
            </ItemsControl>
          </StackPanel>
        </ScrollViewer>

        <!-- Einstellungen -->
        <ScrollViewer x:Name="SettingsPanel" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <StackPanel Margin="0,0,6,0">
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Darstellung" Style="{StaticResource CardTitle}"/>
                <TextBlock Style="{StaticResource Muted}" Text="»System« folgt der Windows-Einstellung für helle bzw. dunkle Apps." Margin="0,0,0,10"/>
                <StackPanel Orientation="Horizontal">
                  <RadioButton x:Name="ThemeSystem" GroupName="Theme" Style="{StaticResource Seg}" Content="System" Tag="System"/>
                  <RadioButton x:Name="ThemeLight" GroupName="Theme" Style="{StaticResource Seg}" Content="Hell" Tag="Hell"/>
                  <RadioButton x:Name="ThemeDark" GroupName="Theme" Style="{StaticResource Seg}" Content="Dunkel" Tag="Dunkel"/>
                </StackPanel>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Komplett-Diagnose" Style="{StaticResource CardTitle}"/>
                <TextBlock Style="{StaticResource Muted}" Margin="0,0,0,6" Text="Diese Bereiche prüft die Komplett-Diagnose – auch in der geplanten Wartung. Abgewählte Bereiche lassen sich jederzeit einzeln auf ihrer Seite mit »Prüfen« starten; der Bericht vermerkt, was nicht geprüft wurde."/>
                <WrapPanel Margin="0,0,0,10">
                  <CheckBox x:Name="ChkAreaFehler" Tag="Fehler" Width="210" Margin="0,3,0,3" Cursor="Hand"><TextBlock Text="Fehlersuche" Foreground="{DynamicResource TextPrimary}"/></CheckBox>
                  <CheckBox x:Name="ChkAreaSpeicher" Tag="Speicher" Width="210" Margin="0,3,0,3" Cursor="Hand"><TextBlock Text="Speicherfresser" Foreground="{DynamicResource TextPrimary}"/></CheckBox>
                  <CheckBox x:Name="ChkAreaLeistung" Tag="Leistung" Width="210" Margin="0,3,0,3" Cursor="Hand"><TextBlock Text="Leistungsbremsen" Foreground="{DynamicResource TextPrimary}"/></CheckBox>
                  <CheckBox x:Name="ChkAreaHerunterfahren" Tag="Herunterfahren" Width="210" Margin="0,3,0,3" Cursor="Hand"><TextBlock Text="Herunterfahren" Foreground="{DynamicResource TextPrimary}"/></CheckBox>
                  <CheckBox x:Name="ChkAreaAkku" Tag="Akku" Width="210" Margin="0,3,0,3" Cursor="Hand"><TextBlock Text="Akku" Foreground="{DynamicResource TextPrimary}"/></CheckBox>
                  <CheckBox x:Name="ChkAreaNetzwerk" Tag="Netzwerk" Width="210" Margin="0,3,0,3" Cursor="Hand"><TextBlock Text="Netzwerk &amp; WLAN" Foreground="{DynamicResource TextPrimary}"/></CheckBox>
                  <CheckBox x:Name="ChkAreaSoftware" Tag="Software" Width="210" Margin="0,3,0,3" Cursor="Hand"><TextBlock Text="Software-Updates" Foreground="{DynamicResource TextPrimary}"/></CheckBox>
                  <CheckBox x:Name="ChkAreaSicherheit" Tag="Sicherheit" Width="210" Margin="0,3,0,3" Cursor="Hand"><TextBlock Text="Sicherheit" Foreground="{DynamicResource TextPrimary}"/></CheckBox>
                  <CheckBox x:Name="ChkAreaWindows" Tag="Windows" Width="210" Margin="0,3,0,3" Cursor="Hand"><TextBlock Text="Windows &amp; Treiber" Foreground="{DynamicResource TextPrimary}"/></CheckBox>
                </WrapPanel>
                <CheckBox x:Name="ChkStorageFull" Margin="0,4,0,6" Cursor="Hand">
                  <TextBlock Text="Speicherbelegung (Kachelgrafik) in die Komplett-Diagnose aufnehmen" Foreground="{DynamicResource TextPrimary}"/>
                </CheckBox>
                <TextBlock Style="{StaticResource Muted}" Text="Liest dafür alle Dateien des Laufwerks ein – die Diagnose dauert ca. 1–2 Minuten länger. Gilt auch für die geplante Wartung. Ohne diese Option lässt sich die Grafik jederzeit im Bereich »Speicherfresser« mit »Prüfen« erstellen."/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Geplante Wartung" Style="{StaticResource CardTitle}"/>
                <TextBlock Style="{StaticResource Muted}" Margin="0,0,0,8" Text="Prüft das Gerät regelmäßig im Hintergrund – ohne Änderungen. Bericht und Verlauf werden gespeichert, kritische Probleme erscheinen als Windows-Benachrichtigung."/>
                <TextBlock x:Name="MaintStatus" Text="Status wird geladen …" Foreground="{DynamicResource TextPrimary}" FontWeight="SemiBold" Margin="0,0,0,10" TextWrapping="Wrap"/>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                  <TextBlock Text="Häufigkeit" Width="100" VerticalAlignment="Center" Foreground="{DynamicResource TextSecondary}"/>
                  <RadioButton x:Name="IntWeekly" GroupName="Interval" Style="{StaticResource Seg}" Content="Wöchentlich" IsChecked="True"/>
                  <RadioButton x:Name="IntDaily" GroupName="Interval" Style="{StaticResource Seg}" Content="Täglich"/>
                </StackPanel>
                <StackPanel x:Name="DayRow" Orientation="Horizontal" Margin="0,0,0,8">
                  <TextBlock Text="Wochentag" Width="100" VerticalAlignment="Center" Foreground="{DynamicResource TextSecondary}"/>
                  <RadioButton x:Name="Day1" GroupName="Day" Style="{StaticResource Seg}" Content="Mo" Tag="Monday" IsChecked="True"/>
                  <RadioButton x:Name="Day2" GroupName="Day" Style="{StaticResource Seg}" Content="Di" Tag="Tuesday"/>
                  <RadioButton x:Name="Day3" GroupName="Day" Style="{StaticResource Seg}" Content="Mi" Tag="Wednesday"/>
                  <RadioButton x:Name="Day4" GroupName="Day" Style="{StaticResource Seg}" Content="Do" Tag="Thursday"/>
                  <RadioButton x:Name="Day5" GroupName="Day" Style="{StaticResource Seg}" Content="Fr" Tag="Friday"/>
                  <RadioButton x:Name="Day6" GroupName="Day" Style="{StaticResource Seg}" Content="Sa" Tag="Saturday"/>
                  <RadioButton x:Name="Day7" GroupName="Day" Style="{StaticResource Seg}" Content="So" Tag="Sunday"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                  <TextBlock Text="Uhrzeit" Width="100" VerticalAlignment="Center" Foreground="{DynamicResource TextSecondary}"/>
                  <TextBox x:Name="MaintTime" Text="10:00" Width="70" Padding="6,4" Background="{DynamicResource InputBg}" Foreground="{DynamicResource TextPrimary}" BorderBrush="{DynamicResource ButtonBorder}"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="BtnMaintSet" Style="{StaticResource BtnPrimary}" Margin="0" Content="Einrichten / Aktualisieren"/>
                  <Button x:Name="BtnMaintRemove" Style="{StaticResource Btn}" Content="Entfernen"/>
                </StackPanel>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Berichte" Style="{StaticResource CardTitle}"/>
                <TextBlock Style="{StaticResource Muted}" Margin="0,0,0,8" Text="Speicherort für Berichte, Verlauf, Änderungsprotokoll und Einstellungen. Ein lokaler Ordner ist schneller als ein von OneDrive synchronisierter."/>
                <DockPanel Margin="0,0,0,12">
                  <Button x:Name="BtnReportFolderChange" DockPanel.Dock="Right" Style="{StaticResource Btn}" Content="Ändern …"/>
                  <Button x:Name="BtnReportFolderOpen" DockPanel.Dock="Right" Style="{StaticResource Btn}" Content="Öffnen"/>
                  <TextBox x:Name="ReportFolderText" IsReadOnly="True" Padding="8,6" VerticalContentAlignment="Center" Background="{DynamicResource InputBg}"
                           Foreground="{DynamicResource TextPrimary}" BorderBrush="{DynamicResource ButtonBorder}"/>
                </DockPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                  <TextBlock Text="Aufbewahren" Width="100" VerticalAlignment="Center" Foreground="{DynamicResource TextSecondary}"/>
                  <RadioButton x:Name="Keep10" GroupName="Keep" Style="{StaticResource Seg}" Content="Neueste 10" Tag="10"/>
                  <RadioButton x:Name="Keep30" GroupName="Keep" Style="{StaticResource Seg}" Content="Neueste 30" Tag="30"/>
                  <RadioButton x:Name="Keep100" GroupName="Keep" Style="{StaticResource Seg}" Content="Neueste 100" Tag="100"/>
                  <RadioButton x:Name="Keep0" GroupName="Keep" Style="{StaticResource Seg}" Content="Alle" Tag="0"/>
                </StackPanel>
                <TextBlock Style="{StaticResource Muted}" Margin="0,0,0,8" Text="Ältere Berichte werden beim Speichern eines neuen Berichts automatisch gelöscht (je Berichtsart). Verlauf und Änderungsprotokoll bleiben immer erhalten."/>
                <CheckBox x:Name="ChkPdf" Margin="0,4,0,12" Cursor="Hand">
                  <TextBlock Text="Berichte zusätzlich als PDF speichern (über Microsoft Edge)" Foreground="{DynamicResource TextPrimary}"/>
                </CheckBox>
                <TextBlock Style="{StaticResource Muted}" Margin="0,0,0,8" Text="Geräteübersicht: Die JSON-Berichte (Diagnosebericht_*.json) mehrerer PCs und Laptops in einen gemeinsamen Ordner legen – z. B. USB-Stick oder OneDrive – und daraus eine Vergleichsübersicht erstellen."/>
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="BtnFleet" Style="{StaticResource Btn}" Margin="0" Content="Geräteübersicht erstellen …"/>
                </StackPanel>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Programm-Updates" Style="{StaticResource CardTitle}"/>
                <TextBlock x:Name="UpdateStatus" Style="{StaticResource Muted}" Margin="0,0,0,10" Text="Updates werden erst nach Ihrer Bestätigung installiert. Prüfsumme und Signatur werden vorher kontrolliert."/>
                <CheckBox x:Name="ChkAutoUpdate" Margin="0,0,0,12" Cursor="Hand">
                  <TextBlock Text="Beim Start automatisch nach Updates suchen" Foreground="{DynamicResource TextPrimary}"/>
                </CheckBox>
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="BtnUpdateCheck" Style="{StaticResource Btn}" Margin="0" Content="Nach Updates suchen"/>
                  <Button x:Name="BtnUpdateInstall" Style="{StaticResource BtnSuccess}" Content="Update installieren" Visibility="Collapsed"/>
                </StackPanel>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Ausgeblendete Meldungen" Style="{StaticResource CardTitle}"/>
                <TextBlock x:Name="HiddenHint" Style="{StaticResource Muted}" Margin="0,0,0,8" Text="Ausgeblendete Meldungen erscheinen bei Prüfungen nicht mehr und zählen nicht in den Gesundheitswert."/>
                <ItemsControl x:Name="HiddenList">
                  <ItemsControl.ItemTemplate>
                    <DataTemplate>
                      <DockPanel Margin="0,3">
                        <Button DockPanel.Dock="Right" Tag="{Binding Key}" Content="Wieder einblenden" Style="{StaticResource Btn}" Padding="10,4"/>
                        <StackPanel>
                          <TextBlock Text="{Binding Title}" Foreground="{DynamicResource TextPrimary}" TextWrapping="Wrap"/>
                          <TextBlock Text="{Binding Meta}" Foreground="{DynamicResource TextMuted}" FontSize="11"/>
                        </StackPanel>
                      </DockPanel>
                    </DataTemplate>
                  </ItemsControl.ItemTemplate>
                </ItemsControl>
                <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                  <Button x:Name="BtnUnhideAll" Style="{StaticResource Btn}" Margin="0" Content="Alle wieder einblenden"/>
                </StackPanel>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Über PC Repair Pro" Style="{StaticResource CardTitle}"/>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,12">
                  <Image x:Name="AboutLogo" Width="96" Height="96" Margin="0,0,18,0" VerticalAlignment="Center" RenderOptions.BitmapScalingMode="HighQuality"/>
                  <StackPanel VerticalAlignment="Center">
                    <TextBlock FontSize="28" FontWeight="Black">
                      <Run Text="PC REPAIR " Foreground="{DynamicResource TextHeading}"/><Run Text="PRO" Foreground="#1E90FF"/>
                    </TextBlock>
                    <TextBlock Text="DIAGNOSE  •  REPAIR  •  KEEP IT RUNNING" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextMuted}" Margin="0,2,0,0"/>
                  </StackPanel>
                </StackPanel>
                <TextBlock x:Name="AboutText" Foreground="{DynamicResource TextPrimary}" TextWrapping="Wrap" Margin="0,0,0,8"
                           Text="PC Repair Pro&#x0a;© 2026 Eder Tom – alle Rechte vorbehalten."/>
                <TextBlock x:Name="SignatureText" Style="{StaticResource Muted}"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>

        <TextBox x:Name="LogBox" Visibility="Collapsed" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                 VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Background="{DynamicResource LogBg}" Foreground="{DynamicResource LogText}"
                 BorderThickness="0" Padding="12" TextWrapping="NoWrap"/>
      </Grid>

      <Border Grid.Row="4" Background="{DynamicResource BgCard}" CornerRadius="12" BorderBrush="{DynamicResource Border}" BorderThickness="1" Padding="14,10" Margin="0,14,0,0">
        <DockPanel>
          <StackPanel x:Name="FixButtons" DockPanel.Dock="Right" Orientation="Horizontal">
            <Button x:Name="BtnSelectRecommended" Style="{StaticResource Btn}" Content="Empfohlene auswählen"/>
            <Button x:Name="BtnClearSelection" Style="{StaticResource Btn}" Content="Auswahl aufheben"/>
            <Button x:Name="BtnFix" Style="{StaticResource BtnSuccess}">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE90F;" FontFamily="Segoe MDL2 Assets" Margin="0,0,8,0" VerticalAlignment="Center"/>
                <TextBlock x:Name="BtnFixText" Text="Ausgewählte beheben"/>
              </StackPanel>
            </Button>
          </StackPanel>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <ProgressBar x:Name="Busy" Width="120" Height="6" IsIndeterminate="True" Visibility="Collapsed" Margin="0,0,12,0" Foreground="#0B5CAD"/>
            <TextBlock x:Name="StatusText" Text="Bereit." Foreground="{DynamicResource TextSecondary}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" MaxWidth="520"/>
          </StackPanel>
        </DockPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@

$Script:SelectXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="640" Height="580" MinWidth="460" MinHeight="360" WindowStartupLocation="CenterOwner"
        Background="{DynamicResource BgWindow}" FontFamily="Segoe UI" FontSize="13" ShowInTaskbar="False" ResizeMode="CanResizeWithGrip">
  <Window.Resources>
%PALETTE%
  </Window.Resources>
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel>
      <TextBlock x:Name="DlgTitle" FontSize="18" FontWeight="Bold" Foreground="{DynamicResource TextHeading}" TextWrapping="Wrap"/>
      <TextBlock x:Name="DlgText" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,6,0,12"/>
    </StackPanel>
    <Border Grid.Row="1" Background="{DynamicResource BgCard}" CornerRadius="10" BorderBrush="{DynamicResource Border}" BorderThickness="1">
      <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="12,8">
        <ItemsControl x:Name="DlgList">
          <ItemsControl.ItemTemplate>
            <DataTemplate>
              <CheckBox IsChecked="{Binding IsChecked, Mode=TwoWay}" Margin="0,5" Cursor="Hand">
                <TextBlock Text="{Binding Label}" TextWrapping="Wrap" Foreground="{DynamicResource TextPrimary}"/>
              </CheckBox>
            </DataTemplate>
          </ItemsControl.ItemTemplate>
        </ItemsControl>
      </ScrollViewer>
    </Border>
    <DockPanel Grid.Row="2" Margin="0,14,0,0">
      <StackPanel Orientation="Horizontal">
        <Button x:Name="DlgAll" Content="Alle" Padding="14,7" MinWidth="70"/>
        <Button x:Name="DlgNone" Content="Keine" Padding="14,7" MinWidth="70" Margin="8,0,0,0"/>
      </StackPanel>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="DlgCancel" Content="Abbrechen" Padding="14,7" MinWidth="90" IsCancel="True"/>
        <Button x:Name="DlgOk" Content="Übernehmen" Padding="14,7" MinWidth="110" Margin="8,0,0,0" IsDefault="True"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
'@

$Script:Xaml = $Script:Xaml.Replace('%PALETTE%', (Get-PaletteXaml))
$Script:SelectXaml = $Script:SelectXaml.Replace('%PALETTE%', (Get-PaletteXaml))

#endregion

#region ---------- Hintergrund-Runspace ----------

# Läuft im Hintergrund-Runspace: leitet Konsolenausgaben in die Oberfläche um und lädt die Diagnose-Logik.
$Script:WorkerInit = @'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$global:GuiLineBuffer = ''

function global:Write-Host {
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]$Object,
        $ForegroundColor, $BackgroundColor, [switch]$NoNewline, $Separator
    )
    $text = (@($Object) | ForEach-Object { "$_" }) -join ' '
    $global:GuiLineBuffer += $text
    if (-not $NoNewline) {
        $sync.Log.Enqueue($global:GuiLineBuffer)
        $global:GuiLineBuffer = ''
    }
}
function global:Read-Host { param([Parameter(Position = 0)]$Prompt) '' }
function global:Clear-Host { }

. $EnginePath -BerichtOrdner $BerichtOrdner

function global:Get-GuiSnapshot {
    $list = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $Script:Findings.Count; $i++) {
        $f = $Script:Findings[$i]
        $list.Add([pscustomobject]@{
                Index          = $i
                Category       = $f.Category
                Severity       = $f.Severity
                Title          = $f.Title
                Detail         = $f.Detail
                Items          = [string[]]@($f.Items | Where-Object { $_ })
                Chart          = @($f.Chart | Where-Object { $_ } | ForEach-Object {
                        [pscustomobject]@{ Label = "$($_.Label)"; Value = [double]$_.Value; Text = "$($_.Text)"; X = [double]$_.X; Y = [double]$_.Y; W = [double]$_.W; H = [double]$_.H; Anteil = [double]$_.Anteil; Path = "$($_.Path)" }
                    })
                ChartStyle     = "$($f.ChartStyle)"
                SelectDefault  = [bool[]]@($f.SelectDefault)
                Repeatable     = [bool]$f.Repeatable
                AskFolder      = [bool]$f.AskFolder
                RunOk          = [bool]$f.RunOk
                HideKey        = "$($f.HideKey)"
                CheckKey       = "$($f.CheckKey)"
                Check          = "$($f.Check)"
                Help           = "$($f.Help)"
                FixLabel       = $f.FixLabel
                CanFix         = ([bool]$f.Fix -and -not $f.Fixed)
                Fixed          = [bool]$f.Fixed
                FixResult      = $f.FixResult
                RequiresReboot = [bool]$f.RequiresReboot
                SelectLabels   = [string[]]@($f.SelectLabels | Where-Object { $_ })
                SelectAll      = [bool]$f.SelectAll
            })
    }
    [pscustomobject]@{
        IsSnapshot = $true
        Findings   = $list.ToArray()
        System     = $Script:SystemInfo
        Reboot     = [bool]$Script:RebootNeeded
        Comparison = [string[]]@($Script:LastComparison)
        DeviceKind = (Get-DeviceKind)
        HiddenCount = $Script:HiddenFindings.Count
    }
}
'@

$Script:Sync = [hashtable]::Synchronized(@{ Log = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]' })
$Script:Job = $null
$Script:PendingLoad = $null

function New-Worker {
    $iss = [initialsessionstate]::CreateDefault()
    try { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass } catch { }
    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $Script:Sync)
    $rs.SessionStateProxy.SetVariable('EnginePath', $Script:EnginePath)
    $rs.SessionStateProxy.SetVariable('BerichtOrdner', $BerichtOrdner)
    return $rs
}

function Start-WorkerJob {
    <# Startet Code im Hintergrund-Runspace; $OnDone erhält die Ausgabe, sobald der Code fertig ist. #>
    param([string]$Code, [object[]]$Arguments = @(), [scriptblock]$OnDone, [string]$Status, [switch]$Silent)
    if ($Script:Job) { return $false }
    $ps = [powershell]::Create()
    $ps.Runspace = $Script:Runspace
    $null = $ps.AddScript($Code)
    foreach ($a in $Arguments) { $null = $ps.AddArgument($a) }
    $Script:Job = @{ PS = $ps; Handle = $ps.BeginInvoke(); OnDone = $OnDone; Silent = [bool]$Silent }
    Set-Busy $true $Status
    return $true
}

function Complete-WorkerJob {
    $job = $Script:Job
    $Script:Job = $null
    $output = $null
    $failure = $null
    try { $output = $job.PS.EndInvoke($job.Handle) } catch { $failure = $_.Exception.InnerException; if (-not $failure) { $failure = $_.Exception } }
    foreach ($e in $job.PS.Streams.Error) { Add-LogLine "FEHLER: $e" }
    $job.PS.Dispose()
    Set-Busy $false
    if ($failure) {
        Add-LogLine "FEHLER: $($failure.Message)"
        if (-not $job.Silent) { Show-Message "Bei der Ausführung ist ein Fehler aufgetreten:`n`n$($failure.Message)" 'Fehler' 'Error' }
        return
    }
    if ($job.OnDone) { & $job.OnDone @($output) }
    if ($Script:PendingLoad -and -not $Script:Job) {
        $pending = $Script:PendingLoad
        $Script:PendingLoad = $null
        & $pending
    }
}

#endregion

#region ---------- Darstellung ----------

$Script:Pages = [ordered]@{
    'Alle'          = @{ Kind = 'Findings'; Title = 'Übersicht'; Sub = 'Gesamtzustand des Geräts – alle Ergebnisse nach Dringlichkeit sortiert.' }
    'Fehler'        = @{ Kind = 'Findings'; Title = 'Fehlersuche'; Sub = 'Bluescreens mit Ursachen, Abstürze, Problemgeräte, Dienste, Systemdateien, Datenträger, Speichertest und defekte Verknüpfungen.'; Scan = 'Invoke-ErrorScan' }
    'Sicherheit'    = @{ Kind = 'Findings'; Title = 'Sicherheit'; Sub = 'Datensicherung, Datenschutz, Browser-Erweiterungen, Virenschutz, Ransomware- und PUA-Schutz, SmartScreen, Konten, Fernwartung, Firewall, Secure Boot, TPM, Verschlüsselung, Kernisolierung, UAC, SMB1, Freigaben und veraltete Browser.'; Scan = 'Invoke-SecurityScan' }
    'Speicher'      = @{ Kind = 'Findings'; Title = 'Speicherfresser'; Sub = 'Arbeitsspeicher, freier Speicherplatz, Datenmüll inkl. Browser-Caches, Wiederherstellungspunkte und alte Sicherungen, Speicherbelegung als Grafik – dazu Werkzeuge für Duplikate, große Ordner, Programme und Entwickler-Reste.'; Scan = 'Invoke-MemoryScanDetailed' }
    'Leistung'      = @{ Kind = 'Findings'; Title = 'Leistungsbremsen'; Sub = 'Prozessorlast, Autostart inkl. geplanter Aufgaben und Dienste, Startdauer, Bildwiederholrate, Arbeitsspeicher-Takt, Energie- und Standby-Einstellungen, Laufwerk, Temperatur, Spiele- und Grafikleistung und Zusatzsoftware.'; Scan = 'Invoke-PerformanceScan' }
    'Herunterfahren' = @{ Kind = 'Findings'; Title = 'Herunterfahren & Neustart'; Sub = 'Dauer der letzten Herunterfahrvorgänge, ungewolltes Aufwachen aus dem Energiesparmodus, bremsende Programme, Dienste und Treiber, Wartezeiten, ausstehende Updates und Netzlaufwerke.'; Scan = 'Invoke-ShutdownScan'; ScanText = 'Herunterfahren prüfen' }
    'Akku'          = @{ Kind = 'Findings'; Title = 'Akku'; Sub = 'Gesundheit, Kapazitätsverlauf, Ladezyklen, Ladezustand, Standby und was das Energiesparen verhindert.'; Scan = 'Invoke-BatteryScan' }
    'Netzwerk'      = @{ Kind = 'Findings'; Title = 'Netzwerk & WLAN'; Sub = 'Internetverbindung, WLAN-Signal und -Sicherheit, Netzwerkkabel (LAN), Geschwindigkeit, Latenz, Proxy und WLAN-Treiber.'; Scan = 'Invoke-NetworkScan' }
    'Software'      = @{ Kind = 'Findings'; Title = 'Software-Updates'; Sub = 'Verfügbare Updates für installierte Programme (über WinGet).'; Scan = 'Invoke-SoftwareScan' }
    'Windows'       = @{ Kind = 'Findings'; Title = 'Windows & Treiber'; Sub = 'Windows-Updates, Treiber-Updates, Grafiktreiber, BIOS-Alter und Hersteller-Tools für BIOS und Firmware.'; Scan = 'Invoke-WindowsUpdateScan' }
    'Werkzeuge'     = @{ Kind = 'Findings'; Title = 'Reparatur-Werkzeuge'; Sub = 'Gezielte Reparaturen und Tests – Werkzeug ankreuzen und »Ausgewählte beheben« klicken.'; Scan = 'Invoke-ToolsScan'; ScanText = 'Werkzeuge laden' }
    'Monitor'       = @{ Kind = 'Monitor'; Title = 'Live-Monitor'; Sub = 'Laufende Anzeige von Prozessor, Arbeitsspeicher, Datenträger, Netzwerk und Temperatur mit den größten Verbrauchern – und Aufzeichnung »Was bremst gerade?«.' }
    'Verlauf'       = @{ Kind = 'History'; Title = 'Verlauf & Trends'; Sub = 'Entwicklung der wichtigsten Kennzahlen über alle Komplett-Diagnosen.' }
    'Aenderungen'   = @{ Kind = 'Changes'; Title = 'Änderungen'; Sub = 'Protokoll aller Änderungen mit Rückgängig-Funktion.' }
    'Einstellungen' = @{ Kind = 'Settings'; Title = 'Einstellungen'; Sub = 'Design, Umfang der Komplett-Diagnose, geplante Wartung, Berichte, ausgeblendete Meldungen und Programm-Updates.' }
    'Log'           = @{ Kind = 'Log'; Title = 'Protokoll'; Sub = 'Alle Ausgaben dieser Sitzung. Wird zusätzlich lokal unter %LOCALAPPDATA%\LaptopDiagnose\Protokolle gespeichert.' }
}
$Script:AreaKeys = @('Fehler', 'Speicher', 'Leistung', 'Herunterfahren', 'Akku', 'Netzwerk', 'Software', 'Sicherheit', 'Windows')
$Script:DeviceKind = $null
$Script:CategoryKeys = @('Fehler', 'Sicherheit', 'Speicher', 'Leistung', 'Herunterfahren', 'Akku', 'Netzwerk', 'Software', 'Windows', 'Werkzeuge')
$Script:SeverityOrder = @{ 'Kritisch' = 0; 'Warnung' = 1; 'Info' = 2; 'OK' = 3 }
$Script:Page = 'Alle'
$Script:Items = New-Object System.Collections.Generic.List[object]
$Script:SystemInfo = $null
$Script:RebootPending = $false
$Script:UpdateRelease = $null
$Script:LoadingSettings = $false
$Script:BrushConverter = New-Object System.Windows.Media.BrushConverter

function Get-Brush { param([string]$Hex) $Script:BrushConverter.ConvertFromString($Hex) }

function New-Table {
    <# DataTable als Datenquelle: Zeilen melden Änderungen selbst an die Oberfläche (keine Laufzeit-Kompilierung nötig). #>
    param([object[]]$Columns)
    $t = New-Object System.Data.DataTable
    foreach ($c in $Columns) {
        $col = $t.Columns.Add($c[0], $c[1])
        if ($c[1] -eq [bool]) { $col.DefaultValue = $false }
        elseif ($c[1] -eq [string]) { $col.DefaultValue = '' }
    }
    return , $t
}

$Script:Table = New-Table @(
    @('Index', [int]), @('Order', [int]), @('Key', [string]), @('Category', [string]), @('CategoryTitle', [string]),
    @('Severity', [string]), @('Title', [string]), @('Detail', [string]), @('ItemsText', [string]), @('FixLabel', [string]),
    @('FixText', [string]), @('Status', [string]), @('HasDetail', [bool]), @('HasItems', [bool]), @('HasStatus', [bool]),
    @('CanFix', [bool]), @('IsFixed', [bool]), @('RequiresReboot', [bool]), @('SelectAll', [bool]), @('ShowFix', [bool]),
    @('IsSelected', [bool]), @('SelectLabels', [object]), @('Chart', [object]), @('HasChart', [bool]), @('Tiles', [object]), @('HasTiles', [bool]),
    @('RunOk', [bool]), @('HasPaths', [bool]), @('HideKey', [string]), @('CheckKey', [string]), @('CheckName', [string]), @('CanHide', [bool]), @('AskFolder', [bool]), @('Repeatable', [bool]), @('SelectDefault', [object]),
    @('Help', [string]), @('HasHelp', [bool])
)
$Script:View = New-Object System.Data.DataView($Script:Table)
$Script:View.Sort = 'Order ASC'

#region Einstellungen und Design

function Get-SettingsPath { Join-Path $BerichtOrdner 'Einstellungen.json' }

function Read-UiSettings {
    $s = [ordered]@{ Design = 'System'; Pdf = $false; AutoUpdate = $true; BerichteBehalten = 30; SpeicherInKomplett = $false }
    try {
        if (Test-Path -LiteralPath (Get-SettingsPath)) {
            $j = [IO.File]::ReadAllText((Get-SettingsPath), [Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $s[$p.Name] = $p.Value }
        }
    } catch { }
    return $s
}

function Write-UiSetting {
    param([string]$Name, $Value)
    $s = Read-UiSettings
    $s[$Name] = $Value
    try {
        if (-not (Test-Path -LiteralPath $BerichtOrdner)) { $null = New-Item -ItemType Directory -Path $BerichtOrdner -Force }
        [IO.File]::WriteAllText((Get-SettingsPath), ([pscustomobject]$s | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))
    } catch { Add-LogLine "Einstellungen konnten nicht gespeichert werden: $($_.Exception.Message)" }
}

function Test-SystemDarkMode {
    try { return (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop).AppsUseLightTheme -eq 0 } catch { return $false }
}

function Set-Theme {
    param([ValidateSet('System', 'Hell', 'Dunkel')][string]$Mode)
    $dark = ($Mode -eq 'Dunkel') -or ($Mode -eq 'System' -and (Test-SystemDarkMode))
    $Script:CurrentPalette = if ($dark) { $Script:Palettes.Dunkel } else { $Script:Palettes.Hell }
    foreach ($k in $Script:CurrentPalette.Keys) { $Script:Window.Resources[$k] = Get-Brush $Script:CurrentPalette[$k] }
}

#endregion

function Show-Message {
    param([string]$Text, [string]$Title = 'PC Repair Pro', [string]$Icon = 'Information', [string]$Buttons = 'OK')
    return [System.Windows.MessageBox]::Show($Script:Window, $Text, $Title, $Buttons, $Icon)
}

function Add-LogLine {
    param([string]$Line)
    $Script:UI.LogBox.AppendText($Line + [Environment]::NewLine)
    if ($Script:UI.LogBox.IsVisible) { $Script:UI.LogBox.ScrollToEnd() }
    $null = $Script:LogBuffer.AppendLine($Line)
}

function Save-LogBuffer {
    <# Schreibt gesammelte Protokollzeilen gebündelt (statt Zeile für Zeile) in die lokale Protokolldatei. #>
    if (-not $Script:LogBuffer -or $Script:LogBuffer.Length -eq 0) { return }
    try {
        [IO.File]::AppendAllText($Script:LogFile, $Script:LogBuffer.ToString(), [Text.Encoding]::UTF8)
        $null = $Script:LogBuffer.Clear()
    } catch { }
    $Script:LastLogFlush = [DateTime]::UtcNow
}

function Set-Busy {
    param([bool]$On, [string]$Status)
    $Script:UI.Busy.Visibility = if ($On) { 'Visible' } else { 'Collapsed' }
    foreach ($b in 'BtnFullScan', 'BtnScanPage', 'BtnReport', 'BtnMaintSet', 'BtnMaintRemove', 'BtnFleet', 'BtnUpdateCheck', 'BtnUpdateInstall') { $Script:UI[$b].IsEnabled = -not $On }
    Update-FixButtons
    if ($Status) { $Script:UI.StatusText.Text = $Status }
    elseif (-not $On) { $Script:UI.StatusText.Text = 'Bereit.' }
}

function Update-FixButtons {
    $readOnly = [bool]$Script:UI.ChkNurPruefen.IsChecked
    $busy = [bool]$Script:Job
    $selected = @($Script:Items | Where-Object { $_.IsSelected -and $_.CanFix }).Count
    $Script:UI.BtnFixText.Text = if ($selected) { "Ausgewählte beheben ($selected)" } else { 'Ausgewählte beheben' }
    $Script:UI.BtnFix.IsEnabled = (-not $busy) -and (-not $readOnly) -and $selected -gt 0
    $Script:UI.BtnSelectRecommended.IsEnabled = (-not $busy) -and (-not $readOnly)
    $Script:UI.BtnClearSelection.IsEnabled = (-not $busy) -and $selected -gt 0
}

function New-ChartView {
    param($Chart)
    $points = @($Chart)
    if (-not $points) { return $null }
    $t = New-Table @(@('Label', [string]), @('Text', [string]), @('BarWidth', [double]))
    $max = [double](($points | Measure-Object Value -Maximum).Maximum)
    if ($max -le 0) { $max = 1 }
    foreach ($p in $points) { $null = $t.Rows.Add("$($p.Label)", "$($p.Text)", [math]::Max(2, [double]$p.Value / $max * 300)) }
    return $t.DefaultView
}

$Script:TreemapColors = @('#1570EF', '#0E9384', '#7A5AF8', '#DC6803', '#079455', '#C11574', '#3E4784', '#B54708', '#155EEF', '#667085')
$Script:TreemapWidth = 700
$Script:TreemapHeight = 280

function New-TreemapView {
    <# Kachelgrafik: Positionen kommen als Anteile (0–1) aus der Diagnose und werden hier auf Pixel umgerechnet. #>
    param($Chart)
    $points = @($Chart)
    if (-not $points) { return $null }
    $t = New-Table @(@('X', [double]), @('Y', [double]), @('W', [double]), @('H', [double]), @('Label', [string]), @('Text', [string]), @('Tip', [string]), @('Fill', [object]), @('ShowText', [bool]), @('Path', [string]), @('Cursor', [object]))
    for ($i = 0; $i -lt $points.Count; $i++) {
        $p = $points[$i]
        $w = [math]::Max(1, $p.W * $Script:TreemapWidth)
        $h = [math]::Max(1, $p.H * $Script:TreemapHeight)
        $brush = Get-Brush $Script:TreemapColors[$i % $Script:TreemapColors.Count]
        $brush.Freeze()
        $tip = '{0}: {1} ({2} %)' -f $p.Label, $p.Text, $p.Anteil
        if ($p.Path) { $tip += "`nKlicken, um die Unterordner anzuzeigen" }
        $null = $t.Rows.Add($p.X * $Script:TreemapWidth, $p.Y * $Script:TreemapHeight, $w, $h, "$($p.Label)", "$($p.Text)",
            $tip, $brush, ($w -ge 70 -and $h -ge 36), "$($p.Path)", $(if ($p.Path) { [System.Windows.Input.Cursors]::Hand } else { [System.Windows.Input.Cursors]::Arrow }))
    }
    return $t.DefaultView
}

function Update-FromSnapshot {
    param($Snapshot)
    if (-not $Snapshot) { return }
    $Script:SystemInfo = $Snapshot.System
    $Script:RebootPending = [bool]$Snapshot.Reboot
    $keep = @{}
    foreach ($it in $Script:Items) { if ($it.IsSelected) { $keep[$it.Key] = $true } }
    $Script:Items.Clear()
    $Script:Table.Rows.Clear()
    $readOnly = [bool]$Script:UI.ChkNurPruefen.IsChecked
    foreach ($f in $Snapshot.Findings) {
        $vm = $Script:Table.NewRow()
        $vm.Index = $f.Index
        $vm.Order = $Script:SeverityOrder[$f.Severity] * 10000 + $f.Index
        $vm.Key = "$($f.Category)|$($f.Title)"
        $vm.Category = $f.Category
        $vm.CategoryTitle = $Script:Pages[$f.Category].Title
        $vm.Severity = $f.Severity
        $vm.Title = $f.Title
        $vm.Detail = "$($f.Detail)"
        $vm.HasDetail = [bool]$f.Detail
        $vm.ItemsText = (@($f.Items) -join [Environment]::NewLine)
        $vm.HasItems = @($f.Items).Count -gt 0
        $vm.HasPaths = $vm.ItemsText -match '[A-Za-z]:\\|%USERPROFILE%'
        if ($f.ChartStyle -eq 'Kacheln') {
            $tileView = New-TreemapView $f.Chart
            if ($tileView) { $vm.Tiles = $tileView; $vm.HasTiles = $true }
        } else {
            $chartView = New-ChartView $f.Chart
            if ($chartView) { $vm.Chart = $chartView; $vm.HasChart = $true }
        }
        $vm.FixLabel = "$($f.FixLabel)"
        $vm.CanFix = [bool]$f.CanFix
        $vm.IsFixed = [bool]$f.Fixed
        $vm.RequiresReboot = [bool]$f.RequiresReboot
        $vm.SelectLabels = [string[]]@($f.SelectLabels)
        $vm.SelectAll = [bool]$f.SelectAll
        $vm.SelectDefault = [bool[]]@($f.SelectDefault)
        $vm.RunOk = [bool]$f.RunOk
        $vm.AskFolder = [bool]$f.AskFolder
        $vm.Repeatable = [bool]$f.Repeatable
        $vm.HideKey = "$($f.HideKey)"
        $vm.CheckKey = "$($f.CheckKey)"
        $vm.CheckName = "$($f.Check)"
        $vm.Help = "$($f.Help)"
        $vm.HasHelp = [bool]$f.Help
        $vm.CanHide = ($f.Severity -ne 'OK') -and -not $f.Repeatable -and $f.Category -ne 'Werkzeuge' -and [bool]$f.HideKey
        $fixText = if ($f.Category -eq 'Werkzeuge' -or $f.Repeatable) { "Ausführen: $($f.FixLabel)" } else { "Beheben: $($f.FixLabel)" }
        if ($f.RequiresReboot) { $fixText += '  (Neustart nötig)' }
        if ($vm.SelectLabels.Count -gt 0) { $fixText += '  – Auswahl im nächsten Schritt' }
        $vm.FixText = $fixText
        if ($f.Fixed) { $vm.Status = "✔ $(if ($f.Category -eq 'Werkzeuge') { 'Ausgeführt' } else { 'Behoben' }): $($f.FixResult)" }
        elseif ($f.RunOk) { $vm.Status = "✔ Ausgeführt: $($f.FixResult)" }
        elseif ($f.FixResult) { $vm.Status = "✖ $($f.FixResult)" }
        $vm.HasStatus = [bool]$vm.Status
        $vm.ShowFix = $vm.CanFix -and -not $readOnly
        $vm.IsSelected = $vm.CanFix -and $keep.ContainsKey($vm.Key)
        $Script:Table.Rows.Add($vm)
        $Script:Items.Add($vm)
    }
    Update-View
}

function Test-FilterActive {
    $ui = $Script:UI
    if (-not $ui.SearchBox) { return $false }
    return [bool]($ui.SearchBox.Text.Trim() -or $ui.FilterSeverity.SelectedIndex -gt 0 -or $ui.ChkOnlyFixable.IsChecked)
}

function ConvertTo-LikeValue {
    <# Suchtext für DataView.RowFilter (LIKE) maskieren. #>
    param([string]$Text)
    $t = $Text -replace "'", "''"
    return ($t -replace '([\[\]\*%])', '[$1]')
}

function Get-FindingsRowFilter {
    param([string]$Kind, [string]$Page)
    $parts = @($(if ($Kind -ne 'Findings' -or $Page -eq 'Alle') { "Category <> 'Werkzeuge'" } else { "Category = '$Page'" }))
    $ui = $Script:UI
    if ($Kind -eq 'Findings' -and $ui.SearchBox) {
        foreach ($word in @($ui.SearchBox.Text.Trim() -split '\s+' | Where-Object { $_ })) {
            $w = ConvertTo-LikeValue $word
            $parts += "(Title LIKE '*$w*' OR Detail LIKE '*$w*' OR ItemsText LIKE '*$w*' OR CheckName LIKE '*$w*' OR CategoryTitle LIKE '*$w*')"
        }
        $tag = "$($ui.FilterSeverity.SelectedItem.Tag)"
        if ($tag) { $parts += '(' + ((@($tag -split ',') | ForEach-Object { "Severity = '$_'" }) -join ' OR ') + ')' }
        if ($ui.ChkOnlyFixable.IsChecked) { $parts += '(CanFix = true AND IsFixed = false)' }
    }
    return ($parts -join ' AND ')
}

function Export-FindingsCsv {
    $sevName = @{ Kritisch = 'Kritisch'; Warnung = 'Warnung'; Info = 'Hinweis'; OK = 'In Ordnung' }
    $rows = foreach ($r in $Script:View) {
        [pscustomobject][ordered]@{
            Bereich    = $r.CategoryTitle
            Schweregrad = $sevName["$($r.Severity)"]
            'Prüfung'  = $r.CheckName
            Titel      = $r.Title
            Details    = $r.Detail
            'Einträge' = (("$($r.ItemsText)" -split "`r?`n" | Where-Object { $_.Trim() }) | ForEach-Object { $_.Trim() }) -join ' | '
            Behebbar   = $(if ($r.CanFix -and -not $r.IsFixed) { 'Ja' } else { 'Nein' })
            Status     = $r.Status
        }
    }
    if (-not $rows) { $null = Show-Message 'Es werden keine Ergebnisse angezeigt, die exportiert werden könnten.' 'CSV-Export'; return }
    $file = Join-Path $BerichtOrdner ('Ergebnisse_{0:yyyyMMdd_HHmm}.csv' -f (Get-Date))
    try {
        # Semikolon und UTF-8 mit BOM: wird von einem deutschen Excel direkt richtig geöffnet
        @($rows) | Export-Csv -LiteralPath $file -Delimiter ';' -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Add-LogLine "CSV-Export: $(@($rows).Count) Ergebnis(se) nach $file"
        Start-Process -FilePath explorer.exe -ArgumentList "/select,`"$file`""
    } catch {
        $null = Show-Message "Die CSV-Datei konnte nicht gespeichert werden:`n`n$($_.Exception.Message)" 'CSV-Export' 'Error'
    }
}

function Update-View {
    $page = $Script:Page
    $def = $Script:Pages[$page]
    $kind = $def.Kind
    $Script:UI.PageTitle.Text = $def.Title
    $Script:UI.PageSubtitle.Text = $def.Sub
    $Script:UI.FindingsScroll.Visibility = if ($kind -eq 'Findings') { 'Visible' } else { 'Collapsed' }
    $Script:UI.HistoryPanel.Visibility = if ($kind -eq 'History') { 'Visible' } else { 'Collapsed' }
    $Script:UI.MonitorPanel.Visibility = if ($kind -eq 'Monitor') { 'Visible' } else { 'Collapsed' }
    if ($kind -eq 'Monitor') { Start-LiveMonitor } else { Stop-LiveMonitor }
    $Script:UI.ChangesPanel.Visibility = if ($kind -eq 'Changes') { 'Visible' } else { 'Collapsed' }
    $Script:UI.SettingsPanel.Visibility = if ($kind -eq 'Settings') { 'Visible' } else { 'Collapsed' }
    $Script:UI.LogBox.Visibility = if ($kind -eq 'Log') { 'Visible' } else { 'Collapsed' }
    $Script:UI.Tiles.Visibility = if ($kind -eq 'Findings') { 'Visible' } else { 'Collapsed' }
    $Script:UI.FixButtons.Visibility = if ($kind -eq 'Findings') { 'Visible' } else { 'Collapsed' }
    if ($kind -eq 'Log') { $Script:UI.LogBox.ScrollToEnd() }
    $Script:UI.BtnScanPage.Visibility = if ($def.Scan) { 'Visible' } else { 'Collapsed' }
    if ($def.Scan) { $Script:UI.BtnScanPageText.Text = $(if ($def.ScanText) { $def.ScanText } else { "$($def.Title) prüfen" }) }

    # Systemübersicht
    if ($page -eq 'Alle' -and $Script:SystemInfo) {
        $info = New-Table @(@('Key', [string]), @('Value', [string]))
        foreach ($k in $Script:SystemInfo.Keys) { $null = $info.Rows.Add($k, "$($Script:SystemInfo[$k])") }
        $Script:UI.SystemList.ItemsSource = $info.DefaultView
        $Script:UI.SystemCard.Visibility = 'Visible'
    } else {
        $Script:UI.SystemCard.Visibility = 'Collapsed'
    }

    $Script:View.RowFilter = Get-FindingsRowFilter $kind $page
    if (-not [object]::ReferenceEquals($Script:UI.FindingsList.ItemsSource, $Script:View)) { $Script:UI.FindingsList.ItemsSource = $Script:View }
    $Script:UI.FilterBar.Visibility = if ($kind -eq 'Findings' -and ($Script:Items.Count -gt 0)) { 'Visible' } else { 'Collapsed' }
    if (-not $Script:View.Count) {
        $Script:UI.EmptyHint.Visibility = 'Visible'
        $Script:UI.EmptyHintText.Text = if (Test-FilterActive) {
            "Keine Ergebnisse für diese Suche bzw. diesen Filter.`nSuchbegriff ändern oder Filter zurücksetzen."
        } elseif ($page -eq 'Alle') {
            "Noch keine Ergebnisse.`nKlicken Sie auf »Komplett-Diagnose starten«, um das Gerät vollständig zu prüfen."
        } elseif ($page -eq 'Werkzeuge') {
            'Die Werkzeuge werden geladen …'
        } else {
            "Dieser Bereich wurde noch nicht geprüft.`nKlicken Sie auf »$($def.Title) prüfen«."
        }
    } else {
        $Script:UI.EmptyHint.Visibility = 'Collapsed'
    }

    # Kacheln (gesamt, ohne Werkzeuge)
    $open = @($Script:Items | Where-Object { -not $_.IsFixed -and $_.Category -ne 'Werkzeuge' })
    $counts = @{}
    foreach ($s in 'Kritisch', 'Warnung', 'Info', 'OK') { $counts[$s] = @($open | Where-Object { $_.Severity -eq $s }).Count }
    $Script:UI.CountKritisch.Text = $counts['Kritisch']
    $Script:UI.CountWarnung.Text = $counts['Warnung']
    $Script:UI.CountInfo.Text = $counts['Info']
    $Script:UI.CountOK.Text = $counts['OK']
    if (@($Script:Items | Where-Object { $_.Category -ne 'Werkzeuge' }).Count) {
        $score = [math]::Max(0, 100 - 15 * $counts['Kritisch'] - 5 * $counts['Warnung'])
        $Script:UI.ScoreText.Text = $score
        $Script:UI.ScoreText.Foreground = Get-Brush $(if ($score -ge 80) { '#079455' } elseif ($score -ge 50) { '#DC8A00' } else { '#D92D20' })
    }

    # Zähler in der Navigation (offene Kritisch + Warnung)
    $openAll = @($Script:Items | Where-Object { -not $_.IsFixed })
    foreach ($cat in $Script:CategoryKeys) {
        $catOpen = @($openAll | Where-Object { $_.Category -eq $cat -and $_.Severity -in 'Kritisch', 'Warnung' })
        $badge = $Script:UI["Badge$cat"]
        if ($catOpen.Count) {
            $Script:UI["Badge${cat}Text"].Text = $catOpen.Count
            $badge.Background = Get-Brush $(if ($catOpen | Where-Object { $_.Severity -eq 'Kritisch' }) { '#D92D20' } else { '#DC8A00' })
            $badge.Visibility = 'Visible'
        } else {
            $badge.Visibility = 'Collapsed'
        }
    }
    Update-FixButtons
}

function Show-SelectionDialog {
    param([string]$Title, [string]$Text, [string[]]$Labels, [bool]$AllChecked, [bool[]]$Defaults)
    $dlg = [Windows.Markup.XamlReader]::Parse($Script:SelectXaml)
    foreach ($k in $Script:CurrentPalette.Keys) { $dlg.Resources[$k] = Get-Brush $Script:CurrentPalette[$k] }
    $dlg.Owner = $Script:Window
    $dlg.Title = $Title
    $dlg.FindName('DlgTitle').Text = $Title
    $dlg.FindName('DlgText').Text = $Text
    $options = New-Table @(@('Label', [string]), @('IsChecked', [bool]))
    for ($i = 0; $i -lt $Labels.Count; $i++) {
        $checked = if ($Defaults -and $i -lt $Defaults.Count) { $Defaults[$i] } else { $AllChecked }
        $null = $options.Rows.Add($Labels[$i], $checked)
    }
    $dlg.FindName('DlgList').ItemsSource = $options.DefaultView
    $dlg.FindName('DlgAll').Add_Click({ foreach ($o in $options.Rows) { $o.IsChecked = $true } }.GetNewClosure())
    $dlg.FindName('DlgNone').Add_Click({ foreach ($o in $options.Rows) { $o.IsChecked = $false } }.GetNewClosure())
    $dlg.FindName('DlgOk').Add_Click({ $dlg.DialogResult = $true }.GetNewClosure())
    if (-not $dlg.ShowDialog()) { return $null }
    $idx = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $options.Rows.Count; $i++) { if ($options.Rows[$i].IsChecked) { $idx.Add($i) } }
    return , $idx.ToArray()
}

#endregion

#region ---------- Aktionen ----------

function Start-Scan {
    param([string[]]$Commands, [string]$Status, [switch]$Full)
    $code = @'
param($cmds, $full)
if (-not $Script:SystemInfo -or $full) { $null = Get-SystemOverview }
if ($full) { $cmds = Get-FullScanOrder }
foreach ($c in $cmds) { & $c }
if ($full) { $null = Save-History }
Get-GuiSnapshot
'@
    $null = Start-WorkerJob -Code $code -Arguments @($Commands, [bool]$Full) -Status $Status -OnDone {
        param($out)
        Update-FromSnapshot (@($out) | Where-Object { $_.IsSnapshot } | Select-Object -Last 1)
        $n = @($Script:Items | Where-Object { $_.CanFix -and $_.Severity -in 'Kritisch', 'Warnung' }).Count
        $Script:UI.StatusText.Text = if ($n) { "Prüfung abgeschlossen – $n Problem(e) können behoben werden." } else { 'Prüfung abgeschlossen.' }
    }
}

function Import-Tools {
    if ($Script:Job) { $Script:PendingLoad = 'Import-Tools'; return }
    Start-Scan -Commands @('Invoke-ToolsScan') -Status 'Werkzeuge werden geladen …'
}

function Invoke-SelectedFixes {
    $chosen = @($Script:Items | Where-Object { $_.IsSelected -and $_.CanFix } | Sort-Object Order)
    if (-not $chosen) { return }

    # Teilauswahl (Autostarts, einzelne Updates, Zusatz-Apps) abfragen
    $requests = New-Object System.Collections.Generic.List[object]
    $labels = New-Object System.Collections.Generic.List[string]
    foreach ($vm in $chosen) {
        $selection = $null
        if ($vm.SelectLabels.Count -gt 0) {
            $text = if ($vm.FixLabel -match 'Autostart') {
                'Markieren Sie die Programme, die NICHT mehr automatisch starten sollen. Virenschutz sowie Touchpad-, Audio- und Grafiktreiber-Tools sollten aktiv bleiben. Rückgängig jederzeit unter »Änderungen«.'
            } elseif ($vm.FixLabel -match 'Verknüpfungen') {
                'Markieren Sie die defekten Verknüpfungen, die bereinigt werden sollen. Verknüpfungen kommen in den Papierkorb, Autostart-Einträge werden deaktiviert (rückgängig über »Änderungen«).'
            } elseif ($vm.FixLabel -match 'doppelte Dateien') {
                'Vorausgewählt sind alle Kopien außer jeweils der ältesten Datei einer Gruppe (»Vorschlag: behalten«). Passen Sie die Auswahl bei Bedarf an – von jeder Gruppe bleibt zur Sicherheit immer mindestens eine Datei erhalten. Gelöscht wird in den Papierkorb.'
            } elseif ($vm.FixLabel -match 'Entwickler-Reste') {
                'Vorausgewählt sind Reste aus Projekten, die seit über 30 Tagen nicht geändert wurden. Diese Ordner enthalten keinen eigenen Code und entstehen beim nächsten Bauen bzw. Starten des Projekts neu. Gelöscht wird in den Papierkorb.'
            } elseif ($vm.FixLabel -match 'leere Ordner') {
                'Markieren Sie die leeren Ordner, die in den Papierkorb verschoben werden sollen.'
            } elseif ($vm.FixLabel -match 'ENDGÜLTIG') {
                'ACHTUNG: Diese Einträge passen nicht in den Papierkorb. Was Sie hier markieren, wird ENDGÜLTIG gelöscht und lässt sich nicht wiederherstellen.'
            } elseif ($vm.FixLabel -match 'Ordner komplett') {
                'Markieren Sie die Ordner, die KOMPLETT mit allen Unterordnern und Dateien gelöscht werden sollen. Sie landen im Papierkorb; was nicht hineinpasst, wird nur nach einer weiteren ausdrücklichen Bestätigung endgültig gelöscht.'
            } elseif ($vm.FixLabel -match 'Downloads') {
                'Markieren Sie die Dateien, die in den Papierkorb verschoben werden sollen. Von dort lassen sie sich bei Bedarf wiederherstellen.'
            } elseif ($vm.FixLabel -match 'Zusatz-Apps') {
                'Markieren Sie die Apps, die entfernt werden sollen. Sie lassen sich bei Bedarf über den Microsoft Store neu installieren.'
            } elseif ($vm.FixLabel -match 'Programme deinstallieren') {
                'Markieren Sie die Programme, die deinstalliert werden sollen. Für jedes Programm startet dessen eigener Deinstaller – bitte dessen Fenster bestätigen. Danach werden zurückgebliebene Ordner angeboten.'
            } elseif ($vm.FixLabel -match 'Programm-Reste') {
                'Markieren Sie die zurückgebliebenen Ordner, die in den Papierkorb verschoben werden sollen.'
            } elseif ($vm.FixLabel -match 'geplante Aufgaben') {
                'Markieren Sie die Aufgaben, die nicht mehr bei Anmeldung bzw. Systemstart laufen sollen. Rückgängig jederzeit unter »Änderungen«.'
            } elseif ($vm.FixLabel -match 'Dienste') {
                'Markieren Sie die Dienste, die nur noch bei Bedarf starten sollen (»Manuell«). Im Zweifel nichts ändern. Rückgängig jederzeit unter »Änderungen«.'
            } elseif ($vm.FixLabel -match 'Datenschutz') {
                'Markieren Sie die Einstellungen, die auf datensparsame Werte gesetzt werden sollen. Rückgängig jederzeit unter »Änderungen«.'
            } elseif ($vm.FixLabel -match 'Wiederherstellungspunkte') {
                'Wählen Sie die gewünschten Maßnahmen. Gelöschte Wiederherstellungspunkte lassen sich nicht zurückholen – der neueste bleibt immer erhalten.'
            } elseif ($vm.FixLabel -match 'Systemabbilder') {
                'Markieren Sie die älteren Systemabbilder, die gelöscht werden sollen. Das neueste Abbild je Computer wird nie angeboten.'
            } elseif ($vm.FixLabel -match 'Treiberpakete') {
                'Markieren Sie die alten, nicht benutzten Treiberpakete, die entfernt werden sollen. Der aktive Treiber bleibt immer erhalten.'
            } elseif ($vm.FixLabel -match 'Weckberechtigung') {
                'Markieren Sie die Geräte, die den Computer nicht mehr aufwecken sollen. Vorausgewählt sind Mäuse und Netzwerkadapter; die Tastatur bleibt zum Aufwecken nutzbar. Rückgängig jederzeit unter »Änderungen«.'
            } elseif ($vm.FixLabel -match 'Spiele-Einstellungen') {
                'Markieren Sie die Einstellungen, die gesetzt werden sollen. Die GPU-Planung wirkt erst nach einem Neustart. Rückgängig jederzeit unter »Änderungen«.'
            } elseif ($vm.FixLabel -match 'Update') {
                'Markieren Sie die Updates, die installiert werden sollen.'
            } else { 'Markieren Sie die Einträge, die bearbeitet werden sollen.' }
            $selection = Show-SelectionDialog -Title $vm.FixLabel -Text $text -Labels $vm.SelectLabels -AllChecked $vm.SelectAll -Defaults ([bool[]]@($vm.SelectDefault))
            if ($null -eq $selection -or $selection.Count -eq 0) { continue }
            $labels.Add("• $($vm.FixLabel) ($($selection.Count) ausgewählt)")
        } else {
            $labels.Add("• $($vm.FixLabel)")
        }
        # Such-Werkzeuge: Standard-Orte oder eigener Ordner
        $folder = $null
        if ($vm.AskFolder) {
            $q = Show-Message "$($vm.FixLabel)`n`nIn den Benutzerordnern suchen (Dokumente, Bilder, Videos, Musik, Desktop, Downloads)?`n`n»Nein« wählt einen anderen Ordner oder ein Laufwerk." 'Wo suchen?' 'Question' 'YesNoCancel'
            if ("$q" -eq 'Cancel') { $labels.RemoveAt($labels.Count - 1); continue }
            if ("$q" -eq 'No') {
                $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
                $dlg.Description = "$($vm.FixLabel): Ordner oder Laufwerk wählen"
                if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { $labels.RemoveAt($labels.Count - 1); continue }
                $folder = $dlg.SelectedPath
                $labels[$labels.Count - 1] = "• $($vm.FixLabel) in $folder"
            }
        }
        $requests.Add(@{ Index = $vm.Index; Selection = $selection; Folder = $folder; AskFolder = [bool]$vm.AskFolder })
    }
    if (-not $requests.Count) { return }

    $warn = ''
    if ($chosen | Where-Object { $_.FixLabel -match 'beenden' }) {
        $warn = "`n`nAchtung: Beim Beenden von Programmen gehen ungespeicherte Daten verloren."
    }
    if ($chosen | Where-Object { $_.FixLabel -match 'ENDGÜLTIG' }) {
        $warn += "`n`nACHTUNG: Ein Teil wird ENDGÜLTIG gelöscht und lässt sich nicht wiederherstellen."
    }
    $answer = Show-Message ("Folgende Maßnahmen werden jetzt ausgeführt:`n`n" + ($labels -join "`n") + $warn + "`n`nFortfahren?") 'Ausführen' 'Question' 'YesNo'
    if ("$answer" -ne 'Yes') { return }

    # Reine Such-Werkzeuge ändern nichts – dann ist kein Wiederherstellungspunkt nötig
    $rp = 'No'
    if ($chosen | Where-Object { -not $_.Repeatable }) {
        $rp = Show-Message "Vor den Änderungen einen Systemwiederherstellungspunkt erstellen?`n(Empfohlen – damit lässt sich der vorherige Zustand wiederherstellen.)" 'Wiederherstellungspunkt' 'Question' 'YesNoCancel'
        if ("$rp" -eq 'Cancel') { return }
    }

    $code = @'
param($requests, $restore)
$list = foreach ($r in $requests) {
    $f = $Script:Findings[$r.Index]
    $f.Selection = $r.Selection
    if ($r.AskFolder) { $f.FixData = @{ Folder = $r.Folder } }
    $f
}
Invoke-FixList -Findings @($list) -RestorePoint:$restore
Get-GuiSnapshot
'@
    $null = Start-WorkerJob -Code $code -Arguments @($requests.ToArray(), ("$rp" -eq 'Yes')) -Status 'Maßnahmen werden ausgeführt …' -OnDone {
        param($out)
        $before = @($Script:Items | Where-Object { $_.IsSelected } | ForEach-Object { $_.Key })
        $snap = @($out) | Where-Object { $_.IsSnapshot } | Select-Object -Last 1
        Update-FromSnapshot $snap
        foreach ($it in $Script:Items) { $it.IsSelected = $false }
        $done = @($Script:Items | Where-Object { $_.Key -in $before })
        $ok = @($done | Where-Object { $_.IsFixed -or $_.RunOk }).Count
        $failed = @($done | Where-Object { -not $_.IsFixed -and -not $_.RunOk -and $_.HasStatus }).Count
        Update-FixButtons
        $msg = "$ok Maßnahme(n) erfolgreich ausgeführt."
        if ($failed) { $msg += "`n$failed Maßnahme(n) fehlgeschlagen – Details in den Ergebniskarten und im Protokoll." }
        $Script:UI.StatusText.Text = $msg -replace "`n", ' '
        if ($snap -and @($snap.Comparison).Count) {
            $msg += "`n`nVorher → Nachher:`n" + ((@($snap.Comparison) | ForEach-Object { '• ' + ($_ -replace '\s{2,}', ' ') }) -join "`n")
            $msg += "`n`nStartzeit und Dauer des Herunterfahrens lassen sich erst nach dem nächsten Neustart vergleichen (Bereich »Verlauf«)."
        }
        if ($Script:RebootPending) {
            $r = Show-Message "$msg`n`nEinige Änderungen werden erst nach einem Neustart wirksam.`nJetzt neu starten? (Vorher alle Dateien speichern!)" 'Neustart' 'Question' 'YesNo'
            if ("$r" -eq 'Yes') {
                $null = Start-WorkerJob -Code '$null = Export-Report -Quiet; Restart-Computer -Force' -Status 'Bericht wird gespeichert, Neustart …'
            }
        } else {
            $null = Show-Message $msg 'Fertig'
        }
    }
}

function Open-Report {
    $null = Start-WorkerJob -Code 'Export-Report -Quiet' -Status 'Bericht wird erstellt …' -OnDone {
        param($out)
        $path = @($out) | Where-Object { $_ -is [string] -and $_ -like '*.html' } | Select-Object -Last 1
        if ($path) {
            $Script:UI.StatusText.Text = "Bericht gespeichert: $path"
            # Über den Explorer öffnen: kehrt sofort zurück, das Programmfenster wird nicht blockiert
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$path`""
        }
    }
}

function Import-History {
    $code = @'
$entries = @(Get-HistoryEntries)
$lastOhne = if ($entries) { @($entries[-1].Ohne | Where-Object { $_ }) } else { @() }
[pscustomobject]@{ IsHistory = $true; Count = $entries.Count; Series = @(Get-MetricSeries -Entries $entries); LastOhne = [string[]]$lastOhne }
'@
    if ($Script:Job) { $Script:PendingLoad = 'Import-History'; return }
    $null = Start-WorkerJob -Code $code -Status 'Verlauf wird geladen …' -Silent -OnDone {
        param($out)
        $h = @($out) | Where-Object { $_.IsHistory } | Select-Object -Last 1
        if (-not $h) { return }
        $t = New-Table @(@('Label', [string]), @('ValueText', [string]), @('TrendText', [string]), @('Trend', [string]), @('RangeText', [string]), @('Points', [object]), @('Stroke', [object]))
        foreach ($s in @($h.Series)) {
            $vals = @($s.Values)
            $min = ($vals | Measure-Object -Minimum).Minimum
            $max = ($vals | Measure-Object -Maximum).Maximum
            $range = if ($max -eq $min) { 1 } else { $max - $min }
            $pc = New-Object System.Windows.Media.PointCollection
            for ($i = 0; $i -lt $vals.Count; $i++) {
                $x = if ($vals.Count -gt 1) { 2 + 268 * $i / ($vals.Count - 1) } else { 136 }
                $y = 52 - 48 * ($vals[$i] - $min) / $range
                $pc.Add((New-Object System.Windows.Point($x, $y)))
            }
            if ($vals.Count -eq 1) { $pc.Add((New-Object System.Windows.Point(140, $pc[0].Y))) }
            $color = switch ($s.Trend) { 'besser' { '#079455' } 'schlechter' { '#DC8A00' } default { '#1570EF' } }
            $dates = @($s.Dates)
            $rangeText = if ($dates.Count -gt 1) { "$($dates.Count) Messungen: $($dates[0]) – $($dates[-1])" } else { "1 Messung: $($dates[0])" }
            if ($null -ne $s.PerMonth -and [math]::Abs([double]$s.PerMonth) -ge 0.05) { $rangeText += ('  ·  ca. {0:+0.##;−0.##} {1} pro Monat' -f [double]$s.PerMonth, $s.Unit) }
            $null = $t.Rows.Add($s.Label, $s.ValueText, $s.TrendText, $s.Trend, $rangeText, $pc, (Get-Brush $color))
        }
        $Script:UI.HistoryList.ItemsSource = $t.DefaultView
        $Script:UI.HistoryHint.Text = if ($h.Count -eq 0) { 'Noch kein Verlauf vorhanden. Nach jeder Komplett-Diagnose (und jeder geplanten Wartung) wird ein Messpunkt gespeichert.' }
        elseif ($h.Count -eq 1) { 'Eine Messung gespeichert. Ab der zweiten Komplett-Diagnose werden Trends sichtbar.' }
        else { "$($h.Count) Messungen gespeichert. Grün = verbessert, Orange = verschlechtert seit der ersten Messung." }
        if (@($h.LastOhne).Count) { $Script:UI.HistoryHint.Text += " Letzte Messung ohne: $(@($h.LastOhne) -join ', ') (in den Einstellungen abgewählt) – Zählungen sind daher nur bedingt vergleichbar." }
    }
}

function Import-Changes {
    if ($Script:Job) { $Script:PendingLoad = 'Import-Changes'; return }
    $null = Start-WorkerJob -Code '[pscustomobject]@{ IsChanges = $true; Entries = @(Get-ChangeLog) }' -Status 'Änderungen werden geladen …' -Silent -OnDone {
        param($out)
        $c = @($out) | Where-Object { $_.IsChanges } | Select-Object -Last 1
        if (-not $c) { return }
        $t = New-Table @(@('Id', [string]), @('Beschreibung', [string]), @('Meta', [string]), @('Note', [string]), @('HasNote', [bool]), @('CanUndo', [bool]), @('Undone', [bool]), @('Sort', [string]))
        foreach ($e in @($c.Entries)) {
            $time = try { ([datetime]$e.Zeit).ToString('dd.MM.yyyy HH:mm') } catch { "$($e.Zeit)" }
            $undone = $e.Status -ne 'Aktiv'
            $meta = $time
            if ($undone) { $meta += "  ·  $($e.Status)$(if ($e.Rueckgaengig) { ' am ' + ([datetime]$e.Rueckgaengig).ToString('dd.MM.yyyy HH:mm') })" }
            elseif (-not $e.Umkehrbar) { $meta += '  ·  nicht automatisch umkehrbar' }
            $note = (@($e.Ergebnis, $e.Hinweis) | Where-Object { $_ }) -join '  ·  '
            $null = $t.Rows.Add("$($e.Id)", "$($e.Beschreibung)", $meta, $note, [bool]$note, ([bool]$e.Umkehrbar -and -not $undone), $undone, "$($e.Zeit)")
        }
        $v = $t.DefaultView
        $v.Sort = 'Sort DESC'
        $Script:UI.ChangesList.ItemsSource = $v
        $Script:UI.ChangesHint.Text = if ($t.Rows.Count) { "$($t.Rows.Count) Änderung(en) protokolliert. Umkehrbare Änderungen lassen sich einzeln zurücknehmen." } else { 'Bisher wurden keine Änderungen vorgenommen.' }
    }
}

function Undo-ChangeUi {
    param([string]$Id, [string]$Text)
    $r = Show-Message "Diese Änderung rückgängig machen?`n`n$Text" 'Rückgängig machen' 'Question' 'YesNo'
    if ("$r" -ne 'Yes') { return }
    $null = Start-WorkerJob -Code 'param($id) Undo-Change -Id $id; [pscustomobject]@{ IsUndo = $true; Reboot = [bool]$Script:RebootNeeded }' -Arguments @($Id) -Status 'Änderung wird rückgängig gemacht …' -OnDone {
        param($out)
        $u = @($out) | Where-Object { $_.IsUndo } | Select-Object -Last 1
        $msg = (@($out) | Where-Object { $_ -is [string] } | Select-Object -Last 1)
        $Script:UI.StatusText.Text = "$msg"
        if ($u -and $u.Reboot) { $null = Show-Message "$msg`n`nDie Änderung wird nach einem Neustart vollständig wirksam." 'Rückgängig gemacht' }
        Import-Changes
    }
}

function Import-SettingsPage {
    $Script:LoadingSettings = $true
    $s = Read-UiSettings
    switch ("$($s.Design)") { 'Hell' { $Script:UI.ThemeLight.IsChecked = $true } 'Dunkel' { $Script:UI.ThemeDark.IsChecked = $true } default { $Script:UI.ThemeSystem.IsChecked = $true } }
    $Script:UI.ChkPdf.IsChecked = [bool]$s.Pdf
    $Script:UI.ChkAutoUpdate.IsChecked = [bool]$s.AutoUpdate
    $Script:UI.ChkStorageFull.IsChecked = [bool]$s.SpeicherInKomplett
    $off = @($s.KomplettOhne | Where-Object { $_ } | ForEach-Object { "$_" })
    foreach ($k in $Script:AreaKeys) { $Script:UI["ChkArea$k"].IsChecked = ($off -notcontains $k) }
    $Script:UI.ChkAreaAkku.Visibility = if ($Script:DeviceKind -eq 'Desktop') { 'Collapsed' } else { 'Visible' }
    $keep = 30
    try { $keep = [int]$s.BerichteBehalten } catch { }
    $keepButton = $Script:UI["Keep$keep"]
    if (-not $keepButton) { $keepButton = $Script:UI.Keep30 }
    $keepButton.IsChecked = $true
    $Script:UI.ReportFolderText.Text = $BerichtOrdner
    Import-HiddenList
    $Script:LoadingSettings = $false

    $sig = @()
    foreach ($f in @($Script:EnginePath, $PSCommandPath)) {
        try {
            $a = Get-AuthenticodeSignature -FilePath $f
            $who = if ($a.SignerCertificate) { ($a.SignerCertificate.Subject -split ',')[0] -replace '^CN=', '' } else { '' }
            $sig += '{0}: {1}' -f [IO.Path]::GetFileName($f), $(switch ("$($a.Status)") {
                    'Valid' { "signiert von $who" }
                    'NotSigned' { 'nicht signiert' }
                    { $_ -in 'UnknownError', 'NotTrusted' -and $a.SignerCertificate } { "signiert von $who (selbst ausgestelltes Zertifikat)" }
                    default { "Signatur ungültig ($($a.Status))" }
                })
        } catch { }
    }
    $Script:UI.SignatureText.Text = "Installationsordner: $PSScriptRoot`nBerichtsordner: $BerichtOrdner`n" + ($sig -join "`n")

    if ($Script:Job) { $Script:PendingLoad = 'Import-SettingsPage'; return }
    $null = Start-WorkerJob -Code '[pscustomobject]@{ IsMaint = $true; Task = (Get-MaintenanceTask); Version = $Script:ToolVersion }' -Status 'Einstellungen werden geladen …' -Silent -OnDone {
        param($out)
        $m = @($out) | Where-Object { $_.IsMaint } | Select-Object -Last 1
        if (-not $m) { return }
        if ($m.Task) {
            $t = $m.Task
            $txt = "Eingerichtet: $($t.Beschreibung)"
            if ($t.NaechsterLauf) { $txt += ('  ·  nächster Lauf {0:dd.MM.yyyy HH:mm}' -f $t.NaechsterLauf) }
            if ($t.LetzterLauf) { $txt += ('  ·  zuletzt {0:dd.MM.yyyy HH:mm}' -f $t.LetzterLauf) }
            $Script:UI.MaintStatus.Text = $txt
            $Script:UI.BtnMaintRemove.Visibility = 'Visible'
        } else {
            $Script:UI.MaintStatus.Text = 'Derzeit ist keine geplante Wartung eingerichtet.'
            $Script:UI.BtnMaintRemove.Visibility = 'Collapsed'
        }
        if (-not $Script:UpdateRelease) { $Script:UI.UpdateStatus.Text = "Installierte Version: $($m.Version). Updates werden erst nach Ihrer Bestätigung installiert; Prüfsumme und Signatur werden vorher kontrolliert." }
    }
}

function Set-ReportFolderUi {
    <# Neuen Berichtordner wählen und vorhandene Daten auf Wunsch mitnehmen. #>
    if ($Script:Job) { $null = Show-Message 'Bitte warten, bis die laufende Aufgabe beendet ist.' 'Berichtordner'; return }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Ordner für Berichte, Verlauf und Einstellungen wählen (darin wird der Unterordner »LaptopDiagnose« verwendet)'
    $dlg.ShowNewFolderButton = $true
    $dlg.SelectedPath = Split-Path -Parent $BerichtOrdner
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $new = $dlg.SelectedPath.TrimEnd('\')
    if ((Split-Path -Leaf $new) -ne 'LaptopDiagnose') { $new = Join-Path $new 'LaptopDiagnose' }
    if ($new.TrimEnd('\') -eq $BerichtOrdner.TrimEnd('\')) { return }
    if (Test-OneDrivePath $new) {
        $w = Show-Message "Der gewählte Ordner wird von OneDrive synchronisiert:`n$new`n`nDas Speichern von Berichten kann dort spürbar langsamer sein. Trotzdem verwenden?" 'Berichtordner' 'Warning' 'YesNo'
        if ("$w" -ne 'Yes') { return }
    }
    $r = Show-Message "Neuer Speicherort:`n$new`n`nVorhandene Berichte, Verlauf, Änderungsprotokoll und Einstellungen dorthin verschieben?`n`n»Nein« lässt sie am alten Ort (Verlauf und Rückgängig-Liste beginnen dann neu)." 'Berichtordner' 'Question' 'YesNoCancel'
    if ("$r" -eq 'Cancel') { return }
    $code = @'
param($from, $to, $move)
if (-not (Test-Path -LiteralPath $to)) { $null = New-Item -ItemType Directory -Path $to -Force }
$msg = "Berichtordner geändert: $to"
if ($move) {
    $res = Move-ReportFolderContent -From $from -To $to
    $msg += " ($($res.Moved) Datei(en) verschoben"
    if ($res.Failed) { $msg += ", $($res.Failed) nicht verschiebbar (bleiben am alten Ort)" }
    $msg += ')'
} else {
    $settings = Join-Path $from 'Einstellungen.json'
    if ((Test-Path -LiteralPath $settings) -and -not (Test-Path -LiteralPath (Join-Path $to 'Einstellungen.json'))) { Copy-Item -LiteralPath $settings -Destination $to }
}
Save-ReportFolderSetting -Path $to
$global:BerichtOrdner = $to
[pscustomobject]@{ IsFolder = $true; Folder = $to; Message = $msg }
'@
    $null = Start-WorkerJob -Code $code -Arguments @($BerichtOrdner, $new, ("$r" -eq 'Yes')) -Status 'Berichtordner wird geändert …' -OnDone {
        param($out)
        $f = @($out) | Where-Object { $_.IsFolder } | Select-Object -Last 1
        if (-not $f) { return }
        $Script:BerichtOrdner = $f.Folder
        $Script:UI.ReportFolderText.Text = $f.Folder
        Add-LogLine $f.Message
        $Script:UI.StatusText.Text = $f.Message
        Import-SettingsPage
    }
}

function Get-PathFromDetailLine {
    <# Holt den Pfad aus einer Detailzeile (z. B. »52,2 GB  444720 Dateien  26.09.2026  C:\Users\…«). #>
    param([string]$Line)
    $l = [Environment]::ExpandEnvironmentVariables(($Line -replace '%USERPROFILE%', $env:USERPROFILE))
    # Bei Verknüpfungen (»Name [Ort] → Ziel«) die Verknüpfung selbst ist nicht in der Zeile – dann das Ziel nehmen
    $m = [regex]::Match($l, '[A-Za-z]:\\[^\r\n]*')
    if (-not $m.Success) { return $null }
    $p = $m.Value
    # Anhänge wie »   (geschützt – nur Anzeige)«, »  –  Grund« oder » (fehlt)« abschneiden
    $p = ($p -split '\s{2,}|\s+–\s+|\s+→\s+')[0]
    $p = $p -replace '\s*\((fehlt|Vorschlag: behalten|geschützt[^)]*)\)\s*$', ''
    return $p.Trim().TrimEnd('\')
}

function Open-PathInExplorer {
    <# Ordner öffnen bzw. Datei im Ordner markieren; existiert der Pfad nicht mehr, den nächsten vorhandenen Ordner öffnen. #>
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$Path`""
        $Script:UI.StatusText.Text = "Geöffnet: $Path"
        return
    }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$Path`""
        $Script:UI.StatusText.Text = "Im Explorer markiert: $Path"
        return
    }
    $parent = Split-Path -Parent $Path
    while ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { $parent = Split-Path -Parent $parent }
    if ($parent) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$parent`""
        $Script:UI.StatusText.Text = "Nicht mehr vorhanden: $Path – übergeordneter Ordner geöffnet."
    } else {
        $Script:UI.StatusText.Text = "Nicht mehr vorhanden: $Path"
    }
}

function Hide-FindingUi {
    <# Meldung ausblenden: nur diese Meldung oder alle Meldungen derselben Prüfung. #>
    param($Row)
    if ($Script:Job) { $null = Show-Message 'Bitte warten, bis die laufende Aufgabe beendet ist.' 'Ausblenden'; return }
    $title = "$($Row['Title'])"
    $check = "$($Row['CheckName'])"
    $mode = 'Fund'
    if ($check) {
        $a = Show-Message "Was soll ausgeblendet werden?`n`nJa = nur diese Meldung:`n»$title«`n`nNein = alle Meldungen der Prüfung »$check«`n`nAusgeblendete Meldungen erscheinen bei künftigen Prüfungen nicht mehr und lassen sich unter »Einstellungen › Ausgeblendete Meldungen« wieder einblenden." 'Meldung ausblenden' 'Question' 'YesNoCancel'
        if ("$a" -eq 'Cancel') { return }
        if ("$a" -eq 'No') { $mode = 'Pruefung' }
    } else {
        $a = Show-Message "Diese Meldung ausblenden?`n`n»$title«`n`nSie erscheint bei künftigen Prüfungen nicht mehr und lässt sich unter »Einstellungen › Ausgeblendete Meldungen« wieder einblenden." 'Meldung ausblenden' 'Question' 'YesNo'
        if ("$a" -ne 'Yes') { return }
    }
    $key = if ($mode -eq 'Pruefung') { "$($Row['CheckKey'])" } else { "$($Row['HideKey'])" }
    $label = if ($mode -eq 'Pruefung') { "Alle Meldungen der Prüfung »$check«" } else { $title }
    $s = Read-UiSettings
    $rules = @(@($s.Ausgeblendet) | Where-Object { $_ -and $_.Key -and $_.Key -ne $key })
    $rules += [pscustomobject]@{ Key = $key; Mode = $mode; Title = $label; Category = "$($Row['CategoryTitle'])"; Zeit = (Get-Date).ToString('s') }
    Write-UiSetting 'Ausgeblendet' ([object[]]$rules)
    $null = Start-WorkerJob -Code 'param($k) Hide-FindingsNow -Key $k; Get-GuiSnapshot' -Arguments @($key) -Status 'Meldung wird ausgeblendet …' -Silent -OnDone {
        param($out)
        Update-FromSnapshot (@($out) | Where-Object { $_.IsSnapshot } | Select-Object -Last 1)
        $Script:UI.StatusText.Text = 'Ausgeblendet. Wieder einblenden unter »Einstellungen › Ausgeblendete Meldungen«.'
    }
}

function Import-HiddenList {
    $rules = @(@((Read-UiSettings).Ausgeblendet) | Where-Object { $_ -and $_.Key })
    $t = New-Table @(@('Key', [string]), @('Title', [string]), @('Meta', [string]))
    foreach ($r in $rules | Sort-Object Zeit -Descending) {
        $when = try { ([datetime]$r.Zeit).ToString('dd.MM.yyyy HH:mm') } catch { '' }
        $null = $t.Rows.Add("$($r.Key)", "$($r.Title)", ('{0}{1} · ausgeblendet am {2}' -f "$($r.Category)", $(if ($r.Mode -eq 'Pruefung') { ' · ganze Prüfung' } else { '' }), $when))
    }
    $Script:UI.HiddenList.ItemsSource = $t.DefaultView
    $Script:UI.BtnUnhideAll.Visibility = if ($rules) { 'Visible' } else { 'Collapsed' }
    $Script:UI.HiddenHint.Text = if ($rules) { "$($rules.Count) Regel(n) aktiv. Ausgeblendete Meldungen erscheinen bei Prüfungen nicht mehr und zählen nicht in den Gesundheitswert." } else { 'Keine Meldungen ausgeblendet. Über »Ausblenden« an einer Ergebniskarte lässt sich eine Meldung dauerhaft verbergen.' }
}

function Show-HiddenUi {
    <# Ausgeblendete Meldungen wieder einblenden (eine Regel oder alle). #>
    param([string]$Key)
    if ($Script:Job) { $null = Show-Message 'Bitte warten, bis die laufende Aufgabe beendet ist.' 'Einblenden'; return }
    $s = Read-UiSettings
    $rules = if ($Key) { @(@($s.Ausgeblendet) | Where-Object { $_ -and $_.Key -and $_.Key -ne $Key }) } else { @() }
    Write-UiSetting 'Ausgeblendet' ([object[]]$rules)
    Import-HiddenList
    $null = Start-WorkerJob -Code 'param($k) Show-HiddenNow -Key $k; Get-GuiSnapshot' -Arguments @("$Key") -Status 'Meldungen werden wieder eingeblendet …' -Silent -OnDone {
        param($out)
        Update-FromSnapshot (@($out) | Where-Object { $_.IsSnapshot } | Select-Object -Last 1)
        $Script:UI.StatusText.Text = 'Wieder eingeblendet – die Meldung(en) erscheinen wieder (spätestens bei der nächsten Prüfung).'
    }
}

function Find-ToolUpdate {
    <# Sucht nach einer neueren Programmversion. -BeimStart: still im Hintergrund, fragt nur bei einem Fund nach. #>
    param([switch]$BeimStart)
    $handler = {
        param($out)
        $u = @($out) | Where-Object { $_.PSObject.Properties['IstNeuer'] } | Select-Object -Last 1
        if (-not $u) { return }
        if ($u.IstNeuer) {
            $Script:UpdateRelease = $u.Release
            $Script:UI.UpdateStatus.Text = "Installierte Version: $($u.Aktuell)  ·  Neue Version verfügbar: $($u.Verfuegbar)`n$($u.Release.Notes)"
            $Script:UI.BtnUpdateInstall.Visibility = 'Visible'
            $Script:UI.BadgeUpdate.Visibility = 'Visible'
            $Script:UI.StatusText.Text = "Neue Version $($u.Verfuegbar) verfügbar – unter »Einstellungen« installierbar."
            if ($Script:UpdateCheckAtStart) { Install-ToolUpdateUi }
        } else {
            $Script:UI.UpdateStatus.Text = "Installierte Version: $($u.Aktuell)  ·  Das Programm ist auf dem neuesten Stand."
            $Script:UI.BtnUpdateInstall.Visibility = 'Collapsed'
            $Script:UI.BadgeUpdate.Visibility = 'Collapsed'
            if ($Script:UpdateCheckAtStart) { $Script:UI.StatusText.Text = 'Bereit. Das Programm ist auf dem neuesten Stand.' }
        }
        $Script:UpdateCheckAtStart = $false
    }
    $Script:UpdateCheckAtStart = [bool]$BeimStart
    $status = if ($BeimStart) { 'Suche im Hintergrund nach Programm-Updates …' } else { 'Suche nach Programm-Updates …' }
    $code = if ($BeimStart) { 'Get-ToolUpdateInfo -TimeoutSec 8' } else { 'Get-ToolUpdateInfo' }
    $null = Start-WorkerJob -Code $code -Status $status -Silent:$BeimStart -OnDone $handler
}

function Install-ToolUpdateUi {
    if (-not $Script:UpdateRelease) { return }
    $notes = if ($Script:UpdateRelease.Notes) { "`n`n$($Script:UpdateRelease.Notes)" } else { '' }
    $r = Show-Message "Version $($Script:UpdateRelease.Version) ist verfügbar.$notes`n`nJetzt herunterladen und installieren?`nPrüfsumme und Signatur werden vorher kontrolliert." 'Programm-Update' 'Question' 'YesNo'
    if ("$r" -ne 'Yes') { return }
    $null = Start-WorkerJob -Code 'param($rel) Install-ToolUpdate -Release $rel' -Arguments @($Script:UpdateRelease) -Status 'Update wird installiert …' -OnDone {
        param($out)
        $msg = @($out) | Where-Object { $_ -is [string] } | Select-Object -Last 1
        $Script:UI.BadgeUpdate.Visibility = 'Collapsed'
        $Script:UI.BtnUpdateInstall.Visibility = 'Collapsed'
        $r2 = Show-Message "$msg`n`nJetzt neu starten?" 'Programm-Update' 'Question' 'YesNo'
        if ("$r2" -eq 'Yes') {
            Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Minimized', '-File', "`"$PSCommandPath`"")
            $Script:Window.Close()
        }
    }
}

#region Live-Monitor
$Script:Mon = [hashtable]::Synchronized(@{ Run = $false; Quit = $false; Last = $null; Seq = 0; Rec = $null; RecStart = $null; Error = $null })
$Script:MonJob = $null
$Script:MonTimer = $null
$Script:MonSeen = 0
$Script:MonHist = @{}
$Script:MonRecSeconds = 60

function Start-LiveMonitor {
    $Script:Mon.Run = $true
    if (-not $Script:MonJob) {
        foreach ($k in 'Cpu', 'Ram', 'Disk', 'Net', 'Temp') { $Script:MonHist[$k] = New-Object System.Collections.Generic.List[double] }
        $iss = [initialsessionstate]::CreateDefault()
        try { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass } catch { }
        $rs = [runspacefactory]::CreateRunspace($iss)
        $rs.Open()
        $rs.SessionStateProxy.SetVariable('mon', $Script:Mon)
        $rs.SessionStateProxy.SetVariable('modPath', (Join-Path $PSScriptRoot 'Module\LiveMonitor.ps1'))
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        $null = $ps.AddScript({
                . $modPath
                $st = New-LiveMonitorState
                while (-not $mon.Quit) {
                    if (-not $mon.Run) { Start-Sleep -Milliseconds 400; $st.PrevTime = $null; continue }
                    $t0 = [datetime]::UtcNow
                    try {
                        $smp = Get-LiveSample -State $st
                        $mon.Last = $smp
                        $mon.Seq++
                        if ($null -ne $mon.Rec) { $null = $mon.Rec.Add($smp) }
                    } catch { $mon.Error = "$($_.Exception.Message)" }
                    $wait = 1000 - ([datetime]::UtcNow - $t0).TotalMilliseconds
                    if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]$wait) }
                }
            })
        $Script:MonJob = @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke() }
        $Script:MonTimer = New-Object System.Windows.Threading.DispatcherTimer
        $Script:MonTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $Script:MonTimer.Add_Tick({ try { Update-LiveMonitorUi } catch { Add-LogLine "FEHLER (Live-Monitor): $($_.Exception.Message)" } })
        $Script:MonTimer.Start()
    }
}

function Stop-LiveMonitor {
    <# Beim Verlassen der Seite pausieren – eine laufende Aufzeichnung läuft weiter. #>
    if (-not $Script:MonJob -or $null -ne $Script:Mon.Rec) { return }
    $Script:Mon.Run = $false
}

function Close-LiveMonitor {
    if (-not $Script:MonJob) { return }
    $Script:Mon.Quit = $true
    try { $Script:MonTimer.Stop() } catch { }
    try { $null = $Script:MonJob.PS.BeginStop($null, $null) } catch { }
}

function ConvertTo-MonPoints {
    param($Values, [double]$Max)
    $v = @($Values)
    if (-not $v.Count) { return [System.Windows.Media.PointCollection]::new() }
    if ($Max -le 0) { $Max = 1 }
    $step = 216.0 / 59
    $off = 59 - ($v.Count - 1)
    $pts = for ($i = 0; $i -lt $v.Count; $i++) {
        $y = 47 - [math]::Min(1, [double]$v[$i] / $Max) * 45
        '{0},{1}' -f [math]::Round(($off + $i) * $step, 1).ToString([Globalization.CultureInfo]::InvariantCulture), [math]::Round($y, 1).ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    [System.Windows.Media.PointCollection]::Parse(($pts -join ' '))
}

function Add-MonValue {
    param([string]$Key, $Value)
    $h = $Script:MonHist[$Key]
    $h.Add($(if ($null -eq $Value) { 0 } else { [double]$Value }))
    while ($h.Count -gt 60) { $h.RemoveAt(0) }
}

function Update-LiveMonitorUi {
    if ($Script:Mon.Seq -eq $Script:MonSeen) { return }
    $Script:MonSeen = $Script:Mon.Seq
    $s = $Script:Mon.Last
    if (-not $s) { return }
    foreach ($k in 'Cpu', 'Ram', 'Disk', 'Net', 'Temp') { Add-MonValue $k $(if ($k -eq 'Ram') { $s.RamPct } else { $s.$k }) }
    $peak = { param($k) [math]::Round((@($Script:MonHist[$k]) | Measure-Object -Maximum).Maximum, 0) }
    $ui = $Script:UI
    $ui.MonCpu.Text = if ($null -ne $s.Cpu) { "$([math]::Round($s.Cpu)) %" } else { '–' }
    $ui.MonCpuSub.Text = "Spitze (letzte Minute): $(& $peak 'Cpu') %"
    $ui.MonRam.Text = if ($null -ne $s.RamPct) { "$([math]::Round($s.RamPct)) %" } else { '–' }
    $ui.MonRamSub.Text = '{0:N1} von {1:N1} GB belegt' -f ($s.RamUsed / 1GB), ($s.RamTotal / 1GB)
    $ui.MonDisk.Text = if ($null -ne $s.Disk) { "$([math]::Round($s.Disk)) %" } else { '–' }
    $ui.MonDiskSub.Text = "Spitze (letzte Minute): $(& $peak 'Disk') %"
    $ui.MonNet.Text = Format-MonRate $s.Net
    $ui.MonNetSub.Text = "Spitze: $(Format-MonRate ((@($Script:MonHist['Net']) | Measure-Object -Maximum).Maximum))"
    $ui.MonTemp.Text = if ($null -ne $s.Temp) { "$($s.Temp) °C" } else { '–' }
    $ui.MonTempSub.Text = if ($null -ne $s.Temp) { 'höchster Sensorwert' } else { 'vom Gerät nicht gemeldet' }
    $ui.MonCpuLine.Points = ConvertTo-MonPoints $Script:MonHist['Cpu'] 100
    $ui.MonRamLine.Points = ConvertTo-MonPoints $Script:MonHist['Ram'] 100
    $ui.MonDiskLine.Points = ConvertTo-MonPoints $Script:MonHist['Disk'] 100
    $ui.MonNetLine.Points = ConvertTo-MonPoints $Script:MonHist['Net'] ([math]::Max(100KB, (@($Script:MonHist['Net']) | Measure-Object -Maximum).Maximum))
    $ui.MonTempLine.Points = ConvertTo-MonPoints $Script:MonHist['Temp'] 100

    $top = @($s.Procs | Sort-Object Cpu, Ram -Descending | Select-Object -First 12)
    $maxCpu = [math]::Max(1, (@($top | ForEach-Object { $_.Cpu }) | Measure-Object -Maximum).Maximum)
    $t = New-Table @(@('Name', [string]), @('CpuText', [string]), @('RamText', [string]), @('BarW', [double]))
    foreach ($p in $top) {
        $n = if ($p.Count -gt 1) { "$($p.Name) ($($p.Count)×)" } else { $p.Name }
        $null = $t.Rows.Add($n, ('{0:N1} %' -f $p.Cpu), ('{0:N0} MB' -f ($p.Ram / 1MB)), [math]::Max(1, 110 * $p.Cpu / $maxCpu))
    }
    $ui.MonProcList.ItemsSource = $t.DefaultView

    # Aufzeichnung »Was bremst gerade?«
    $rec = $Script:Mon.Rec
    if ($null -ne $rec) {
        $n = $rec.Count
        $ui.MonRecStatus.Text = "Aufzeichnung läuft: $n von $Script:MonRecSeconds Sekunden – das Gerät dabei normal weiterbenutzen …"
        if ($n -ge $Script:MonRecSeconds) {
            $Script:Mon.Rec = $null
            $a = Get-LoadAnalysis $rec.ToArray()
            $ui.MonRecStatus.Text = "Aufzeichnung vom $(Get-Date -Format 'dd.MM.yyyy HH:mm') ($($a.Samples) Messpunkte):"
            $ui.MonRecVerdict.Text = $a.Verdict
            $ui.MonRecVerdict.Visibility = 'Visible'
            $ui.MonRecDetail.Text = (@($a.Lines) -join [Environment]::NewLine)
            $ui.MonRecDetail.Visibility = 'Visible'
            $ui.BtnMonRecord.IsEnabled = $true
            $ui.BtnMonRecordText.Text = 'Erneut aufzeichnen'
            Add-LogLine "Live-Aufzeichnung: $($a.Verdict)"
            foreach ($l in $a.Lines) { Add-LogLine "   $l" }
            if ($Script:Page -ne 'Monitor') { $Script:Mon.Run = $false }
        }
    }
}

function Start-LoadRecording {
    $Script:Mon.Rec = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    $Script:UI.BtnMonRecord.IsEnabled = $false
    $Script:UI.BtnMonRecordText.Text = 'Aufzeichnung läuft …'
    $Script:UI.MonRecVerdict.Visibility = 'Collapsed'
    $Script:UI.MonRecDetail.Visibility = 'Collapsed'
    $Script:UI.MonRecStatus.Text = 'Aufzeichnung startet …'
    Start-LiveMonitor
}
#endregion

#endregion

#region ---------- Start ----------

try {
    if (-not (Test-Path -LiteralPath $Script:EnginePath)) { throw "Die Datei LaptopDiagnose.ps1 wurde nicht gefunden ($Script:EnginePath)." }
    if (-not (Test-Path -LiteralPath $BerichtOrdner)) { $null = New-Item -ItemType Directory -Path $BerichtOrdner -Force }
    # Protokolle lokal speichern (nicht im ggf. von OneDrive synchronisierten Berichtsordner)
    $logDir = Join-Path $env:LOCALAPPDATA 'LaptopDiagnose\Protokolle'
    if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
    $Script:LogFile = Join-Path $logDir ('Protokoll_GUI_{0:yyyyMMdd_HHmmss}.txt' -f (Get-Date))
    $Script:LogBuffer = New-Object System.Text.StringBuilder
    $Script:LastLogFlush = [DateTime]::UtcNow

    $Script:Window = [Windows.Markup.XamlReader]::Parse($Script:Xaml)
    $icon = Join-Path $PSScriptRoot 'LaptopDiagnose.ico'
    if (Test-Path -LiteralPath $icon) {
        # Symbol in den Speicher laden – sonst bleibt die Datei gesperrt und Programm-Updates können sie nicht ersetzen
        try {
            $iconStream = New-Object System.IO.MemoryStream(, [IO.File]::ReadAllBytes($icon))
            $Script:Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create($iconStream, [System.Windows.Media.Imaging.BitmapCreateOptions]::None, [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
        } catch { }
    }
    # Logo ebenfalls über den Speicher laden (keine Dateisperre)
    $Script:LogoImage = $null
    $logoPath = Join-Path $PSScriptRoot 'Logo.png'
    if (Test-Path -LiteralPath $logoPath) {
        try {
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit()
            $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.StreamSource = New-Object System.IO.MemoryStream(, [IO.File]::ReadAllBytes($logoPath))
            $bmp.EndInit()
            $bmp.Freeze()
            $Script:LogoImage = $bmp
        } catch { }
    }

    $Script:UI = @{}
    $names = @(
        'VersionText', 'ChkNurPruefen', 'BtnReport', 'BtnFolder', 'AdminBanner', 'BtnScanPage', 'BtnScanPageText', 'BtnFullScan',
        'PageTitle', 'PageSubtitle', 'Tiles', 'ScoreText', 'CountKritisch', 'CountWarnung', 'CountInfo', 'CountOK', 'FindingsScroll', 'SystemCard',
        'SystemList', 'EmptyHint', 'EmptyHintText', 'FindingsList', 'LogBox', 'FixButtons', 'BtnSelectRecommended', 'BtnClearSelection', 'BtnFix',
        'BtnFixText', 'Busy', 'StatusText', 'HistoryPanel', 'HistoryHint', 'HistoryList', 'ChangesPanel', 'ChangesHint', 'ChangesList',
        'SettingsPanel', 'ThemeSystem', 'ThemeLight', 'ThemeDark', 'MaintStatus', 'IntWeekly', 'IntDaily', 'DayRow', 'MaintTime', 'BtnMaintSet',
        'BtnMaintRemove', 'ChkPdf', 'BtnFleet', 'UpdateStatus', 'BtnUpdateCheck', 'BtnUpdateInstall', 'SignatureText', 'ChkAutoUpdate', 'BadgeUpdate', 'AboutText', 'SidebarLogo', 'AboutLogo',
         'HiddenHint', 'HiddenList', 'BtnUnhideAll', 'ChkStorageFull', 'ChkAreaFehler', 'ChkAreaSpeicher', 'ChkAreaLeistung', 'ChkAreaHerunterfahren', 'ChkAreaAkku', 'ChkAreaNetzwerk', 'ChkAreaSoftware', 'ChkAreaSicherheit', 'ChkAreaWindows', 'ReportFolderText', 'BtnReportFolderChange', 'BtnReportFolderOpen', 'Keep10', 'Keep30', 'Keep100', 'Keep0',
        'MonitorPanel', 'MonCpu', 'MonCpuSub', 'MonCpuLine', 'MonRam', 'MonRamSub', 'MonRamLine', 'MonDisk', 'MonDiskSub', 'MonDiskLine', 'MonNet', 'MonNetSub', 'MonNetLine',
        'MonTemp', 'MonTempSub', 'MonTempLine', 'BtnMonRecord', 'BtnMonRecordText', 'MonRecStatus', 'MonRecVerdict', 'MonRecDetail',
        'FilterBar', 'SearchBox', 'SearchHint', 'FilterSeverity', 'ChkOnlyFixable', 'BtnExportCsv'
    )
    $navNames = @('NavAlle') + @($Script:CategoryKeys | ForEach-Object { "Nav$_" }) + @('NavMonitor', 'NavVerlauf', 'NavAenderungen', 'NavEinstellungen', 'NavLog')
    $names += $navNames
    $names += @($Script:CategoryKeys | ForEach-Object { "Badge$_"; "Badge${_}Text" })
    $names += 1..7 | ForEach-Object { "Day$_" }
    foreach ($n in $names) {
        $Script:UI[$n] = $Script:Window.FindName($n)
        if ($null -eq $Script:UI[$n]) { throw "Oberflächenelement »$n« fehlt." }
    }

    if ($Script:LogoImage) { $Script:UI.SidebarLogo.Source = $Script:LogoImage; $Script:UI.AboutLogo.Source = $Script:LogoImage }
    Set-Theme -Mode ("$((Read-UiSettings).Design)" -replace '^(?!Hell$|Dunkel$).*$', 'System')
    $Script:UI.ChkNurPruefen.IsChecked = [bool]$NurPruefen
    if (-not $Script:IsAdmin) { $Script:UI.AdminBanner.Visibility = 'Visible' }

    # Navigation
    foreach ($nav in $navNames) {
        $Script:UI[$nav].Add_Checked({
                param($s, $e)
                $Script:Page = [string]$s.Tag
                Update-View
                switch ($Script:Pages[$Script:Page].Kind) {
                    'History' { Import-History }
                    'Changes' { Import-Changes }
                    'Settings' { Import-SettingsPage }
                }
                if ($Script:Page -eq 'Werkzeuge' -and -not ($Script:Items | Where-Object { $_.Category -eq 'Werkzeuge' })) { Import-Tools }
            })
    }

    $Script:UI.BtnFullScan.Add_Click({ Start-Scan -Full -Status 'Komplett-Diagnose läuft (je nach System 3–10 Minuten) …' })
    $Script:UI.BtnScanPage.Add_Click({
            $def = $Script:Pages[$Script:Page]
            if ($def.Scan) { Start-Scan -Commands @($def.Scan) -Status "$($def.Title) wird geprüft …" }
        })
    $Script:UI.BtnSelectRecommended.Add_Click({
            foreach ($it in $Script:Items) {
                if ($it.CanFix -and $it.Severity -in 'Kritisch', 'Warnung' -and ($Script:Page -eq 'Alle' -or $it.Category -eq $Script:Page)) { $it.IsSelected = $true }
            }
            Update-FixButtons
        })
    $Script:UI.BtnClearSelection.Add_Click({
            foreach ($it in $Script:Items) { $it.IsSelected = $false }
            Update-FixButtons
        })
    $Script:UI.BtnFix.Add_Click({ Invoke-SelectedFixes })
    $Script:UI.BtnMonRecord.Add_Click({ Start-LoadRecording })
    $Script:UI.SearchBox.Add_TextChanged({
            $Script:UI.SearchHint.Visibility = if ($Script:UI.SearchBox.Text) { 'Collapsed' } else { 'Visible' }
            Update-View
        })
    $Script:UI.FilterSeverity.Add_SelectionChanged({ if ($Script:UI.FindingsList) { Update-View } })
    $Script:UI.ChkOnlyFixable.Add_Click({ Update-View })
    $Script:UI.BtnExportCsv.Add_Click({ Export-FindingsCsv })
    $Script:UI.BtnReport.Add_Click({ Open-Report })
    $Script:UI.BtnFolder.Add_Click({ Start-Process -FilePath explorer.exe -ArgumentList "`"$BerichtOrdner`"" })
    $Script:UI.ChkNurPruefen.Add_Click({
            $ro = [bool]$Script:UI.ChkNurPruefen.IsChecked
            foreach ($it in $Script:Items) {
                $it.ShowFix = $it.CanFix -and -not $ro
                if ($ro) { $it.IsSelected = $false }
            }
            Update-FixButtons
        })

    # Rückgängig-Schaltflächen in der Änderungsliste
    $Script:UI.ChangesList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
            param($s, $e)
            $btn = $e.OriginalSource
            while ($btn -and -not ($btn -is [System.Windows.Controls.Button])) { $btn = [System.Windows.Media.VisualTreeHelper]::GetParent($btn) }
            if ($btn -and $btn.Tag) { Undo-ChangeUi -Id ([string]$btn.Tag) -Text ([string]$btn.DataContext.Row['Beschreibung']) }
        })

    # Ergebniskarten: »Ausblenden«
    $Script:UI.FindingsList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
            param($s, $e)
            $btn = $e.OriginalSource
            if (-not ($btn -is [System.Windows.Controls.Button]) -or "$($btn.Tag)" -ne 'HideBtn') { return }
            $e.Handled = $true
            Hide-FindingUi $btn.DataContext.Row
        })
    # Einstellungen: ausgeblendete Meldungen wieder einblenden
    $Script:UI.HiddenList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
            param($s, $e)
            $btn = $e.OriginalSource
            if ($btn -is [System.Windows.Controls.Button] -and $btn.Tag) { Show-HiddenUi ([string]$btn.Tag) }
        })
    $Script:UI.BtnUnhideAll.Add_Click({
            $r = Show-Message 'Alle ausgeblendeten Meldungen wieder einblenden?' 'Einblenden' 'Question' 'YesNo'
            if ("$r" -eq 'Yes') { Show-HiddenUi '' }
        })

    # Details: Doppelklick auf eine Zeile mit Pfad öffnet den Ordner im Explorer
    $Script:UI.FindingsList.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent, [System.Windows.Input.MouseButtonEventHandler]{
            param($s, $e)
            if ($e.ClickCount -ne 2) { return }
            $tb = $e.OriginalSource
            while ($tb -and -not ($tb -is [System.Windows.Controls.TextBox] -and "$($tb.Tag)" -eq 'DetailBox')) { $tb = [System.Windows.Media.VisualTreeHelper]::GetParent($tb) }
            if (-not $tb) { return }
            $text = "$($tb.Text)"
            $idx = $tb.GetCharacterIndexFromPoint($e.GetPosition($tb), $true)
            if ($idx -lt 0 -or -not $text) { return }
            # Ganze (logische) Zeile – auch wenn sie im Fenster umbrochen angezeigt wird
            $start = if ($idx -gt 0) { $text.LastIndexOf("`n", [math]::Min($idx, $text.Length) - 1) + 1 } else { 0 }
            $end = $text.IndexOf("`n", [math]::Min($idx, $text.Length))
            if ($end -lt 0) { $end = $text.Length }
            $line = $text.Substring($start, $end - $start).TrimEnd("`r")
            $path = Get-PathFromDetailLine $line
            if (-not $path) { return }
            $e.Handled = $true
            Open-PathInExplorer $path
        }, $true)

    # Kachelgrafik: Klick auf eine Kachel zeigt deren Unterordner
    $Script:UI.FindingsList.AddHandler([System.Windows.UIElement]::MouseLeftButtonUpEvent, [System.Windows.Input.MouseButtonEventHandler]{
            param($s, $e)
            $el = $e.OriginalSource
            while ($el -and -not ($el -is [System.Windows.FrameworkElement] -and "$($el.Tag)" -eq 'TreemapTile')) { $el = [System.Windows.Media.VisualTreeHelper]::GetParent($el) }
            if (-not $el) { return }
            $path = "$($el.DataContext.Row['Path'])"
            if (-not $path -or $Script:Job) { return }
            $null = Start-WorkerJob -Code 'param($p) Invoke-StorageDrillDown -Path $p; Get-GuiSnapshot' -Arguments @($path) -Status "Speicherbelegung von $path wird ermittelt …" -OnDone {
                param($out)
                Update-FromSnapshot (@($out) | Where-Object { $_.IsSnapshot } | Select-Object -Last 1)
                $Script:UI.StatusText.Text = 'Unterordner angezeigt – siehe Karte »Speicherbelegung: …«.'
            }
        }, $true)

    # Einstellungen
    foreach ($t in 'ThemeSystem', 'ThemeLight', 'ThemeDark') {
        $Script:UI[$t].Add_Checked({
                param($s, $e)
                if ($Script:LoadingSettings) { return }
                Set-Theme -Mode ([string]$s.Tag)
                Write-UiSetting 'Design' ([string]$s.Tag)
            })
    }
    $Script:UI.ChkPdf.Add_Click({ Write-UiSetting 'Pdf' ([bool]$Script:UI.ChkPdf.IsChecked) })
    $Script:UI.ChkStorageFull.Add_Click({ Write-UiSetting 'SpeicherInKomplett' ([bool]$Script:UI.ChkStorageFull.IsChecked) })
    foreach ($k in $Script:AreaKeys) {
        $Script:UI["ChkArea$k"].Add_Click({
                param($s, $e)
                # Akku zählt auf Desktop-PCs nicht mit (dort ausgeblendet)
                $visible = @($Script:AreaKeys | Where-Object { -not ($_ -eq 'Akku' -and $Script:DeviceKind -eq 'Desktop') })
                if (-not ($visible | Where-Object { $Script:UI["ChkArea$_"].IsChecked })) {
                    $s.IsChecked = $true
                    $null = Show-Message 'Mindestens ein Bereich muss für die Komplett-Diagnose ausgewählt bleiben.' 'Komplett-Diagnose'
                    return
                }
                $off = @($Script:AreaKeys | Where-Object { -not $Script:UI["ChkArea$_"].IsChecked })
                Write-UiSetting 'KomplettOhne' ([string[]]$off)
            })
    }
    foreach ($k in 'Keep10', 'Keep30', 'Keep100', 'Keep0') {
        $Script:UI[$k].Add_Checked({
                param($s, $e)
                if ($Script:LoadingSettings) { return }
                Write-UiSetting 'BerichteBehalten' ([int]$s.Tag)
            })
    }
    $Script:UI.BtnReportFolderChange.Add_Click({ Set-ReportFolderUi })
    $Script:UI.BtnReportFolderOpen.Add_Click({ Start-Process -FilePath explorer.exe -ArgumentList "`"$BerichtOrdner`"" })
    $Script:UI.IntDaily.Add_Checked({ $Script:UI.DayRow.IsEnabled = $false })
    $Script:UI.IntWeekly.Add_Checked({ $Script:UI.DayRow.IsEnabled = $true })
    $Script:UI.BtnMaintSet.Add_Click({
            $time = $Script:UI.MaintTime.Text.Trim()
            if ($time -notmatch '^([01]\d|2[0-3]):[0-5]\d$') { $null = Show-Message 'Bitte die Uhrzeit im Format HH:mm angeben, z. B. 10:00.' 'Geplante Wartung' 'Warning'; return }
            $interval = if ($Script:UI.IntDaily.IsChecked) { 'Taeglich' } else { 'Woechentlich' }
            $day = (1..7 | ForEach-Object { $Script:UI["Day$_"] } | Where-Object { $_.IsChecked } | Select-Object -First 1).Tag
            $null = Start-WorkerJob -Code 'param($i, $d, $t) Register-MaintenanceTask -Intervall $i -Tag $d -Uhrzeit $t' -Arguments @($interval, [string]$day, $time) -Status 'Geplante Wartung wird eingerichtet …' -OnDone {
                param($out)
                $msg = @($out) | Where-Object { $_ -is [string] } | Select-Object -Last 1
                $null = Show-Message "$msg" 'Geplante Wartung'
                Import-SettingsPage
            }
        })
    $Script:UI.BtnMaintRemove.Add_Click({
            $null = Start-WorkerJob -Code 'Unregister-MaintenanceTask' -Status 'Geplante Wartung wird entfernt …' -OnDone {
                param($out)
                $Script:UI.StatusText.Text = "$(@($out) | Where-Object { $_ -is [string] } | Select-Object -Last 1)"
                Import-SettingsPage
            }
        })
    $Script:UI.BtnFleet.Add_Click({
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = 'Ordner mit den Diagnoseberichten (Diagnosebericht_*.json) mehrerer Geräte auswählen'
            $dlg.SelectedPath = $BerichtOrdner
            if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $null = Start-WorkerJob -Code 'param($o) Export-FleetOverview -Ordner $o' -Arguments @($dlg.SelectedPath) -Status 'Geräteübersicht wird erstellt …' -OnDone {
                param($out)
                $p = @($out) | Where-Object { $_ -is [string] -and $_ -like '*.html' } | Select-Object -Last 1
                if ($p) { $Script:UI.StatusText.Text = "Geräteübersicht gespeichert: $p"; Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$p`"" }
            }
        })
    $Script:UI.BtnUpdateCheck.Add_Click({ Find-ToolUpdate })
    $Script:UI.BtnUpdateInstall.Add_Click({ Install-ToolUpdateUi })
    $Script:UI.ChkAutoUpdate.Add_Click({ Write-UiSetting 'AutoUpdate' ([bool]$Script:UI.ChkAutoUpdate.IsChecked) })

    # Ausgaben des Hintergrund-Runspace übernehmen und fertige Aufträge abschließen
    $Script:Timer = New-Object System.Windows.Threading.DispatcherTimer
    $Script:Timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $Script:Timer.Add_Tick({
            try {
                $line = $null
                while ($Script:Sync.Log.TryDequeue([ref]$line)) {
                    Add-LogLine $line
                    $t = $line.Trim()
                    if ($Script:Job -and $t -match '^(›|▶)') { $Script:UI.StatusText.Text = $t.TrimStart('›', '▶', ' ').TrimEnd('.', ' ') + ' …' }
                }
                if ($Script:Job -and $Script:Job.Handle.IsCompleted) { Complete-WorkerJob }
                if (([DateTime]::UtcNow - $Script:LastLogFlush).TotalSeconds -ge 5) { Save-LogBuffer }
                Update-FixButtons
            } catch {
                Add-LogLine "FEHLER (Oberfläche): $($_.Exception.Message)"
            }
        })

    $Script:Window.Add_Closing({
            param($s, $e)
            if ($Script:Job) {
                $r = Show-Message 'Es läuft noch eine Prüfung oder Reparatur. Trotzdem beenden?' 'Beenden' 'Warning' 'YesNo'
                if ("$r" -ne 'Yes') { $e.Cancel = $true; return }
                try { $null = $Script:Job.PS.BeginStop($null, $null) } catch { }
            }
            $Script:Timer.Stop()
            Close-LiveMonitor
            Save-LogBuffer
        })

    # Immer maximiert und im Vordergrund öffnen – die Konsole wird minimiert gestartet, und Windows würde
    # diesen Zustand sonst auf das erste Programmfenster übertragen
    $Script:Window.Add_Loaded({
            $Script:Window.WindowState = 'Maximized'
            $Script:Window.Topmost = $true
            $null = $Script:Window.Activate()
            $Script:Window.Topmost = $false
        })

    $Script:Runspace = New-Worker
    $Script:Window.Add_ContentRendered({
            $init = $Script:WorkerInit + "`n" + '$null = Get-SystemOverview; $Script:ToolVersion; Get-GuiSnapshot'
            $null = Start-WorkerJob -Code $init -Status 'Systeminformationen werden gelesen …' -OnDone {
                param($out)
                $ver = @($out) | Where-Object { $_ -is [string] } | Select-Object -First 1
                if ($ver) {
                    $Script:UI.VersionText.Text = "Version $ver"
                    $Script:UI.AboutText.Text = "PC Repair Pro  ·  Version $ver  (früher »Laptop-Diagnose & Reparatur«)`n© 2026 Eder Tom – alle Rechte vorbehalten."
                }
                $first = @($out) | Where-Object { $_.IsSnapshot } | Select-Object -Last 1
                Update-FromSnapshot $first
                # Desktop-PC: Akku-Bereich ausblenden
                if ($first) { $Script:DeviceKind = $first.DeviceKind }
                if ($Script:DeviceKind -eq 'Desktop') { $Script:UI.NavAkku.Visibility = 'Collapsed' }
                # Nach einem Programm-Update: Startmenü, Desktop-Verknüpfung und »Installierte Apps« angleichen
                if ($ver) { try { $null = Update-AppRegistration -InstallDir $PSScriptRoot -Version $ver } catch { } }
                if ($Script:FolderMigrationMessage) {
                    Add-LogLine $Script:FolderMigrationMessage
                    $null = Show-Message ($Script:FolderMigrationMessage + ".`n`nDer Ordner lässt sich jederzeit unter »Einstellungen › Berichte« ändern.") 'Berichtordner'
                }
                if ((Read-UiSettings).AutoUpdate) { Find-ToolUpdate -BeimStart }
            }
        })

    Update-View
    $Script:Timer.Start()
    $null = $Script:Window.ShowDialog()
} catch {
    $msg = $_.Exception.Message
    try { $null = [System.Windows.MessageBox]::Show("Die Oberfläche konnte nicht gestartet werden:`n`n$msg", 'PC Repair Pro', 'OK', 'Error') }
    catch { Write-Host "Fehler: $msg" -ForegroundColor Red }
} finally {
    # Hintergrundarbeit beenden, ohne zu blockieren (z. B. eine laufende Update-Suche), und den Prozess sicher schließen
    if ($Script:Job) { try { $null = $Script:Job.PS.BeginStop($null, $null) } catch { } }
    elseif ($Script:Runspace) { try { $Script:Runspace.Close(); $Script:Runspace.Dispose() } catch { } }
    try { if ($Script:Timer) { $Script:Timer.Stop() } } catch { }
    [Environment]::Exit(0)
}

#endregion
