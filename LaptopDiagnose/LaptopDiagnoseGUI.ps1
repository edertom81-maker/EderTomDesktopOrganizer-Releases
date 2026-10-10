#Requires -Version 5.1
<#
.SYNOPSIS
    Grafische Oberfläche für Laptop-Diagnose & Reparatur.

.DESCRIPTION
    Fenster mit Navigation, Ergebniskarten und Schaltflächen. Alle Prüfungen und Reparaturen stammen aus
    LaptopDiagnose.ps1 und laufen in einem Hintergrund-Runspace, damit das Fenster bedienbar bleibt.
    Änderungen am System erfolgen nur nach Auswahl und ausdrücklicher Bestätigung.

.PARAMETER NurPruefen
    Startet mit aktivem Schalter »Nur prüfen« (Reparaturen sind gesperrt).

.PARAMETER BerichtOrdner
    Zielordner für Berichte und Protokolle (Standard: Dokumente\LaptopDiagnose).

.NOTES
    Copyright 2026 by Eder Tom
#>
[CmdletBinding()]
param(
    [switch]$NurPruefen,
    [string]$BerichtOrdner = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'LaptopDiagnose')
)

$Script:EnginePath = Join-Path $PSScriptRoot 'LaptopDiagnose.ps1'
$Script:IsAdmin = $false
try {
    $Script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }

# Mit Administratorrechten und im STA-Modus (für WPF erforderlich) neu starten
$isSta = [Threading.Thread]::CurrentThread.GetApartmentState() -eq [Threading.ApartmentState]::STA
if (-not $Script:IsAdmin -or -not $isSta) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"", '-BerichtOrdner', "`"$BerichtOrdner`"")
    if ($NurPruefen) { $argList += '-NurPruefen' }
    $exe = (Get-Process -Id $PID).Path
    try {
        if ($Script:IsAdmin) { Start-Process -FilePath $exe -ArgumentList $argList -WindowStyle Hidden }
        else { Start-Process -FilePath $exe -ArgumentList $argList -Verb RunAs -WindowStyle Hidden }
        return
    } catch {
        # Rechteabfrage abgelehnt: eingeschränkt weiterarbeiten (nur möglich, wenn bereits STA)
        if (-not $isSta) { return }
    }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

if (-not ('LaptopDiagnose.FindingItem' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System.ComponentModel;
namespace LaptopDiagnose {
    public class NotifyBase : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        protected void Raise(string name) {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h != null) { h(this, new PropertyChangedEventArgs(name)); }
        }
    }
    public class FindingItem : NotifyBase {
        public int Index { get; set; }
        public int Order { get; set; }
        public string Key { get; set; }
        public string Category { get; set; }
        public string CategoryTitle { get; set; }
        public string Severity { get; set; }
        public string Title { get; set; }
        public string Detail { get; set; }
        public string ItemsText { get; set; }
        public string FixLabel { get; set; }
        public string FixText { get; set; }
        public string Status { get; set; }
        public bool HasDetail { get; set; }
        public bool HasItems { get; set; }
        public bool HasStatus { get; set; }
        public bool CanFix { get; set; }
        public bool IsFixed { get; set; }
        public bool RequiresReboot { get; set; }
        public bool SelectAll { get; set; }
        public string[] SelectLabels { get; set; }
        private bool showFix;
        public bool ShowFix { get { return showFix; } set { showFix = value; Raise("ShowFix"); } }
        private bool isSelected;
        public bool IsSelected { get { return isSelected; } set { isSelected = value; Raise("IsSelected"); } }
    }
    public class SelectOption : NotifyBase {
        public string Label { get; set; }
        private bool isChecked;
        public bool IsChecked { get { return isChecked; } set { isChecked = value; Raise("IsChecked"); } }
    }
    public class InfoRow {
        public string Key { get; set; }
        public string Value { get; set; }
    }
}
'@
}

#region ---------- Oberfläche (XAML) ----------

$Script:Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Laptop-Diagnose &amp; Reparatur" Width="1220" Height="820" MinWidth="1000" MinHeight="640"
        WindowStartupLocation="CenterScreen" Background="#F3F5F9" FontFamily="Segoe UI" FontSize="13"
        TextOptions.TextFormattingMode="Display" UseLayoutRounding="True">
  <Window.Resources>
    <BooleanToVisibilityConverter x:Key="B2V"/>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Background" Value="White"/>
      <Setter Property="Foreground" Value="#1D2533"/>
      <Setter Property="BorderBrush" Value="#CBD3DF"/>
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
      <Setter Property="Foreground" Value="#C3CFDF"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Margin" Value="0,2"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="GroupName" Value="Nav"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" Background="Transparent" CornerRadius="8" Padding="12,9">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#1D3350"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="#2A4B76"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="NavIcon" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="16"/>
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
    <Style x:Key="Tile" TargetType="Border">
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="#E2E7EF"/>
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
      <Setter Property="Foreground" Value="#5D6B80"/>
      <Setter Property="HorizontalAlignment" Value="Center"/>
    </Style>

    <DataTemplate x:Key="FindingTemplate">
      <Border Background="White" CornerRadius="10" Margin="0,0,0,10" BorderBrush="#E2E7EF" BorderThickness="1">
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
              <TextBlock DockPanel.Dock="Right" Text="{Binding CategoryTitle}" Foreground="#8A96A8" FontSize="11" Margin="10,3,0,0"/>
              <TextBlock Text="{Binding Title}" FontWeight="SemiBold" FontSize="14" Foreground="#1D2533" TextWrapping="Wrap"/>
            </DockPanel>
            <TextBlock Text="{Binding Detail}" Visibility="{Binding HasDetail, Converter={StaticResource B2V}}"
                       Foreground="#5D6B80" TextWrapping="Wrap" Margin="0,6,0,0"/>
            <Expander Header="Details anzeigen" Visibility="{Binding HasItems, Converter={StaticResource B2V}}" Margin="0,6,0,0" Foreground="#0B5CAD">
              <TextBox Text="{Binding ItemsText, Mode=OneWay}" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                       BorderThickness="0" Background="#F6F8FB" Foreground="#2C3A4F" TextWrapping="Wrap" Padding="10,8" Margin="0,6,0,0"/>
            </Expander>
            <CheckBox IsChecked="{Binding IsSelected, Mode=TwoWay}" Visibility="{Binding ShowFix, Converter={StaticResource B2V}}"
                      Margin="0,10,0,0" Cursor="Hand" VerticalContentAlignment="Center">
              <TextBlock Text="{Binding FixText}" Foreground="#0B4F8A" FontWeight="SemiBold" TextWrapping="Wrap"/>
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
          <Setter TargetName="StatusText" Property="Foreground" Value="#067A46"/>
        </DataTrigger>
      </DataTemplate.Triggers>
    </DataTemplate>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="250"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- Seitenleiste -->
    <Border Background="#13233A">
      <DockPanel>
        <StackPanel DockPanel.Dock="Top" Margin="22,26,22,18">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE90F;" FontFamily="Segoe MDL2 Assets" FontSize="22" Foreground="#5BA7EF" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <TextBlock Text="Laptop-Diagnose" FontSize="19" FontWeight="Bold" Foreground="White" VerticalAlignment="Center"/>
          </StackPanel>
          <TextBlock x:Name="VersionText" Text="&amp; Reparatur" Foreground="#8EA2BD" Margin="32,2,0,0"/>
        </StackPanel>

        <StackPanel DockPanel.Dock="Bottom" Margin="20,10,20,20">
          <CheckBox x:Name="ChkNurPruefen" Foreground="#C3CFDF" Cursor="Hand" Margin="0,0,0,12">
            <TextBlock Text="Nur prüfen (keine Änderungen)" TextWrapping="Wrap"/>
          </CheckBox>
          <Button x:Name="BtnReport" Style="{StaticResource Btn}" Margin="0" Background="#1D3350" Foreground="White" BorderBrush="#2A4B76">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE8A5;" FontFamily="Segoe MDL2 Assets" Margin="0,0,8,0" VerticalAlignment="Center"/>
              <TextBlock Text="Bericht speichern &amp; öffnen"/>
            </StackPanel>
          </Button>
          <Button x:Name="BtnFolder" Style="{StaticResource Btn}" Margin="0,8,0,0" Background="Transparent" Foreground="#8EA2BD" BorderBrush="Transparent" Padding="4">
            <TextBlock Text="Berichtsordner öffnen" TextDecorations="Underline"/>
          </Button>
        </StackPanel>

        <StackPanel Margin="12,0">
          <RadioButton x:Name="NavAlle" Tag="Alle" Style="{StaticResource Nav}" IsChecked="True">
            <DockPanel><TextBlock Text="&#xE80F;" Style="{StaticResource NavIcon}"/><TextBlock Text="Übersicht" VerticalAlignment="Center"/></DockPanel>
          </RadioButton>
          <RadioButton x:Name="NavFehler" Tag="Fehler" Style="{StaticResource Nav}">
            <DockPanel>
              <TextBlock Text="&#xE7BA;" Style="{StaticResource NavIcon}"/>
              <Border x:Name="BadgeFehler" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeFehlerText" Style="{StaticResource BadgeText}"/></Border>
              <TextBlock Text="Fehlersuche" VerticalAlignment="Center"/>
            </DockPanel>
          </RadioButton>
          <RadioButton x:Name="NavSpeicher" Tag="Speicher" Style="{StaticResource Nav}">
            <DockPanel>
              <TextBlock Text="&#xEDA2;" Style="{StaticResource NavIcon}"/>
              <Border x:Name="BadgeSpeicher" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeSpeicherText" Style="{StaticResource BadgeText}"/></Border>
              <TextBlock Text="Speicherfresser" VerticalAlignment="Center"/>
            </DockPanel>
          </RadioButton>
          <RadioButton x:Name="NavLeistung" Tag="Leistung" Style="{StaticResource Nav}">
            <DockPanel>
              <TextBlock Text="&#xE945;" Style="{StaticResource NavIcon}"/>
              <Border x:Name="BadgeLeistung" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeLeistungText" Style="{StaticResource BadgeText}"/></Border>
              <TextBlock Text="Leistungsbremsen" VerticalAlignment="Center"/>
            </DockPanel>
          </RadioButton>
          <RadioButton x:Name="NavAkku" Tag="Akku" Style="{StaticResource Nav}">
            <DockPanel>
              <TextBlock Text="&#xE83F;" Style="{StaticResource NavIcon}"/>
              <Border x:Name="BadgeAkku" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeAkkuText" Style="{StaticResource BadgeText}"/></Border>
              <TextBlock Text="Akku" VerticalAlignment="Center"/>
            </DockPanel>
          </RadioButton>
          <RadioButton x:Name="NavSoftware" Tag="Software" Style="{StaticResource Nav}">
            <DockPanel>
              <TextBlock Text="&#xE896;" Style="{StaticResource NavIcon}"/>
              <Border x:Name="BadgeSoftware" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeSoftwareText" Style="{StaticResource BadgeText}"/></Border>
              <TextBlock Text="Software-Updates" VerticalAlignment="Center"/>
            </DockPanel>
          </RadioButton>
          <RadioButton x:Name="NavWindows" Tag="Windows" Style="{StaticResource Nav}">
            <DockPanel>
              <TextBlock Text="&#xE895;" Style="{StaticResource NavIcon}"/>
              <Border x:Name="BadgeWindows" DockPanel.Dock="Right" Style="{StaticResource Badge}"><TextBlock x:Name="BadgeWindowsText" Style="{StaticResource BadgeText}"/></Border>
              <TextBlock Text="Windows &amp; Treiber" VerticalAlignment="Center"/>
            </DockPanel>
          </RadioButton>
          <Border Height="1" Background="#24395A" Margin="8,10"/>
          <RadioButton x:Name="NavLog" Tag="Log" Style="{StaticResource Nav}">
            <DockPanel><TextBlock Text="&#xE9D9;" Style="{StaticResource NavIcon}"/><TextBlock Text="Protokoll" VerticalAlignment="Center"/></DockPanel>
          </RadioButton>
        </StackPanel>
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

      <Border x:Name="AdminBanner" Background="#FFF4E0" BorderBrush="#F5C26B" BorderThickness="1" CornerRadius="8" Padding="12,8" Margin="0,0,0,14" Visibility="Collapsed">
        <TextBlock TextWrapping="Wrap" Foreground="#7A4A00" Text="Ohne Administratorrechte gestartet: Einige Prüfungen liefern weniger Ergebnisse, und Reparaturen sowie Updates können fehlschlagen. Für den vollen Funktionsumfang das Programm neu starten und die Rechteabfrage bestätigen."/>
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
          <TextBlock x:Name="PageTitle" Text="Übersicht" FontSize="24" FontWeight="Bold" Foreground="#13233A"/>
          <TextBlock x:Name="PageSubtitle" Text="" Foreground="#5D6B80" Margin="0,2,0,0" TextWrapping="Wrap"/>
        </StackPanel>
      </DockPanel>

      <Grid Grid.Row="2" Margin="0,0,-12,16">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="1.3*"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Border Style="{StaticResource Tile}">
          <StackPanel>
            <TextBlock x:Name="ScoreText" Text="–" Style="{StaticResource TileNumber}" Foreground="#8A96A8"/>
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
        <ScrollViewer x:Name="FindingsScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <StackPanel Margin="0,0,6,0">
            <Border x:Name="SystemCard" Background="White" CornerRadius="12" BorderBrush="#E2E7EF" BorderThickness="1" Padding="18,14" Margin="0,0,0,14" Visibility="Collapsed">
              <StackPanel>
                <TextBlock Text="Systemübersicht" FontWeight="Bold" FontSize="15" Foreground="#13233A" Margin="0,0,0,8"/>
                <ItemsControl x:Name="SystemList">
                  <ItemsControl.ItemsPanel>
                    <ItemsPanelTemplate><UniformGrid Columns="2"/></ItemsPanelTemplate>
                  </ItemsControl.ItemsPanel>
                  <ItemsControl.ItemTemplate>
                    <DataTemplate>
                      <DockPanel Margin="0,3,16,3">
                        <TextBlock Text="{Binding Key}" Foreground="#5D6B80" Width="150"/>
                        <TextBlock Text="{Binding Value}" Foreground="#1D2533" TextWrapping="Wrap"/>
                      </DockPanel>
                    </DataTemplate>
                  </ItemsControl.ItemTemplate>
                </ItemsControl>
              </StackPanel>
            </Border>
            <Border x:Name="EmptyHint" Background="White" CornerRadius="12" BorderBrush="#E2E7EF" BorderThickness="1" Padding="24" Visibility="Collapsed">
              <StackPanel HorizontalAlignment="Center">
                <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="34" Foreground="#9AA8BB" HorizontalAlignment="Center"/>
                <TextBlock x:Name="EmptyHintText" Margin="0,10,0,0" Foreground="#5D6B80" TextWrapping="Wrap" TextAlignment="Center" FontSize="14"/>
              </StackPanel>
            </Border>
            <ItemsControl x:Name="FindingsList" ItemTemplate="{StaticResource FindingTemplate}"/>
          </StackPanel>
        </ScrollViewer>
        <TextBox x:Name="LogBox" Visibility="Collapsed" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                 VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Background="#0F1720" Foreground="#D6DEE8"
                 BorderThickness="0" Padding="12" TextWrapping="NoWrap"/>
      </Grid>

      <Border Grid.Row="4" Background="White" CornerRadius="12" BorderBrush="#E2E7EF" BorderThickness="1" Padding="14,10" Margin="0,14,0,0">
        <DockPanel>
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
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
            <TextBlock x:Name="StatusText" Text="Bereit." Foreground="#5D6B80" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" MaxWidth="460"/>
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
        Width="620" Height="560" MinWidth="460" MinHeight="360" WindowStartupLocation="CenterOwner"
        Background="#F3F5F9" FontFamily="Segoe UI" FontSize="13" ShowInTaskbar="False" ResizeMode="CanResizeWithGrip">
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel>
      <TextBlock x:Name="DlgTitle" FontSize="18" FontWeight="Bold" Foreground="#13233A" TextWrapping="Wrap"/>
      <TextBlock x:Name="DlgText" Foreground="#5D6B80" TextWrapping="Wrap" Margin="0,6,0,12"/>
    </StackPanel>
    <Border Grid.Row="1" Background="White" CornerRadius="10" BorderBrush="#E2E7EF" BorderThickness="1">
      <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="12,8">
        <ItemsControl x:Name="DlgList">
          <ItemsControl.ItemTemplate>
            <DataTemplate>
              <CheckBox IsChecked="{Binding IsChecked, Mode=TwoWay}" Margin="0,5" Cursor="Hand">
                <TextBlock Text="{Binding Label}" TextWrapping="Wrap"/>
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
    }
}
'@

$Script:Sync = [hashtable]::Synchronized(@{ Log = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]' })
$Script:Job = $null

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
    param([string]$Code, [object[]]$Arguments = @(), [scriptblock]$OnDone, [string]$Status)
    if ($Script:Job) { return $false }
    $ps = [powershell]::Create()
    $ps.Runspace = $Script:Runspace
    $null = $ps.AddScript($Code)
    foreach ($a in $Arguments) { $null = $ps.AddArgument($a) }
    $Script:Job = @{ PS = $ps; Handle = $ps.BeginInvoke(); OnDone = $OnDone }
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
        Show-Message "Bei der Ausführung ist ein Fehler aufgetreten:`n`n$($failure.Message)" 'Fehler' 'Error'
        return
    }
    if ($job.OnDone) { & $job.OnDone @($output) }
}

#endregion

#region ---------- Darstellung ----------

$Script:Pages = [ordered]@{
    'Alle'     = @{ Title = 'Übersicht'; Sub = 'Gesamtzustand des Laptops – alle Ergebnisse nach Dringlichkeit sortiert.' }
    'Fehler'   = @{ Title = 'Fehlersuche'; Sub = 'Bluescreens, Abstürze, Problemgeräte, Dienste, Systemdateien, Datenträger, Virenschutz und Netzwerk.'; Scan = 'Invoke-ErrorScan' }
    'Speicher' = @{ Title = 'Speicherfresser'; Sub = 'Arbeitsspeicher, größte Programme, freier Speicherplatz, Datenmüll und große Dateien.'; Scan = 'Invoke-MemoryScan' }
    'Leistung' = @{ Title = 'Leistungsbremsen'; Sub = 'Prozessorlast, Autostart, Startdauer, Energieeinstellungen, Laufwerk und Temperatur.'; Scan = 'Invoke-PerformanceScan' }
    'Akku'     = @{ Title = 'Akku'; Sub = 'Gesundheit, Ladezyklen, Ladezustand und was das Energiesparen verhindert.'; Scan = 'Invoke-BatteryScan' }
    'Software' = @{ Title = 'Software-Updates'; Sub = 'Verfügbare Updates für installierte Programme (über WinGet).'; Scan = 'Invoke-SoftwareScan' }
    'Windows'  = @{ Title = 'Windows & Treiber'; Sub = 'Windows-Updates, Treiber-Updates und Hersteller-Tools für BIOS und Firmware.'; Scan = 'Invoke-WindowsUpdateScan' }
    'Log'      = @{ Title = 'Protokoll'; Sub = 'Alle Ausgaben dieser Sitzung. Wird zusätzlich im Berichtsordner gespeichert.' }
}
$Script:SeverityOrder = @{ 'Kritisch' = 0; 'Warnung' = 1; 'Info' = 2; 'OK' = 3 }
$Script:Page = 'Alle'
$Script:Items = New-Object System.Collections.Generic.List[object]
$Script:SystemInfo = $null
$Script:RebootPending = $false
$Script:BrushConverter = New-Object System.Windows.Media.BrushConverter

function Get-Brush { param([string]$Hex) $Script:BrushConverter.ConvertFromString($Hex) }

function Show-Message {
    param([string]$Text, [string]$Title = 'Laptop-Diagnose', [string]$Icon = 'Information', [string]$Buttons = 'OK')
    return [System.Windows.MessageBox]::Show($Script:Window, $Text, $Title, $Buttons, $Icon)
}

function Add-LogLine {
    param([string]$Line)
    $Script:UI.LogBox.AppendText($Line + [Environment]::NewLine)
    if ($Script:UI.LogBox.IsVisible) { $Script:UI.LogBox.ScrollToEnd() }
    try { [IO.File]::AppendAllText($Script:LogFile, $Line + [Environment]::NewLine, [Text.Encoding]::UTF8) } catch { }
}

function Set-Busy {
    param([bool]$On, [string]$Status)
    $Script:UI.Busy.Visibility = if ($On) { 'Visible' } else { 'Collapsed' }
    foreach ($b in 'BtnFullScan', 'BtnScanPage', 'BtnReport') { $Script:UI[$b].IsEnabled = -not $On }
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

function Update-FromSnapshot {
    param($Snapshot)
    if (-not $Snapshot) { return }
    $Script:SystemInfo = $Snapshot.System
    $Script:RebootPending = [bool]$Snapshot.Reboot
    $keep = @{}
    foreach ($it in $Script:Items) { if ($it.IsSelected) { $keep[$it.Key] = $true } }
    $Script:Items.Clear()
    $readOnly = [bool]$Script:UI.ChkNurPruefen.IsChecked
    foreach ($f in $Snapshot.Findings) {
        $vm = New-Object LaptopDiagnose.FindingItem
        $vm.Index = $f.Index
        $vm.Order = $Script:SeverityOrder[$f.Severity] * 10000 + $f.Index
        $vm.Key = "$($f.Category)|$($f.Title)"
        $vm.Category = $f.Category
        $vm.CategoryTitle = $Script:Pages[$f.Category].Title
        $vm.Severity = $f.Severity
        $vm.Title = $f.Title
        $vm.Detail = $f.Detail
        $vm.HasDetail = [bool]$f.Detail
        $vm.ItemsText = (@($f.Items) -join [Environment]::NewLine)
        $vm.HasItems = @($f.Items).Count -gt 0
        $vm.FixLabel = $f.FixLabel
        $vm.CanFix = [bool]$f.CanFix
        $vm.IsFixed = [bool]$f.Fixed
        $vm.RequiresReboot = [bool]$f.RequiresReboot
        $vm.SelectLabels = [string[]]@($f.SelectLabels)
        $vm.SelectAll = [bool]$f.SelectAll
        $fixText = "Beheben: $($f.FixLabel)"
        if ($f.RequiresReboot) { $fixText += '  (Neustart nötig)' }
        if ($vm.SelectLabels.Count -gt 0) { $fixText += '  – Auswahl im nächsten Schritt' }
        $vm.FixText = $fixText
        if ($f.Fixed) { $vm.Status = "✔ Behoben: $($f.FixResult)" }
        elseif ($f.FixResult) { $vm.Status = "✖ $($f.FixResult)" }
        $vm.HasStatus = [bool]$vm.Status
        $vm.ShowFix = $vm.CanFix -and -not $readOnly
        $vm.IsSelected = $vm.CanFix -and $keep.ContainsKey($vm.Key)
        $Script:Items.Add($vm)
    }
    Update-View
}

function Update-View {
    $page = $Script:Page
    $def = $Script:Pages[$page]
    $Script:UI.PageTitle.Text = $def.Title
    $Script:UI.PageSubtitle.Text = $def.Sub
    $isLog = $page -eq 'Log'
    $Script:UI.LogBox.Visibility = if ($isLog) { 'Visible' } else { 'Collapsed' }
    $Script:UI.FindingsScroll.Visibility = if ($isLog) { 'Collapsed' } else { 'Visible' }
    if ($isLog) { $Script:UI.LogBox.ScrollToEnd() }
    $Script:UI.BtnScanPage.Visibility = if ($def.Scan) { 'Visible' } else { 'Collapsed' }
    if ($def.Scan) { $Script:UI.BtnScanPageText.Text = "$($def.Title) prüfen" }

    # Systemübersicht
    if ($page -eq 'Alle' -and $Script:SystemInfo) {
        $rows = foreach ($k in $Script:SystemInfo.Keys) {
            $r = New-Object LaptopDiagnose.InfoRow
            $r.Key = $k; $r.Value = "$($Script:SystemInfo[$k])"
            $r
        }
        $Script:UI.SystemList.ItemsSource = @($rows)
        $Script:UI.SystemCard.Visibility = 'Visible'
    } else {
        $Script:UI.SystemCard.Visibility = 'Collapsed'
    }

    $visible = @($Script:Items | Where-Object { $page -eq 'Alle' -or $_.Category -eq $page } | Sort-Object Order)
    $Script:UI.FindingsList.ItemsSource = $visible
    if (-not $visible.Count) {
        $Script:UI.EmptyHint.Visibility = 'Visible'
        $Script:UI.EmptyHintText.Text = if ($page -eq 'Alle') {
            "Noch keine Ergebnisse.`nKlicken Sie auf »Komplett-Diagnose starten«, um den Laptop vollständig zu prüfen."
        } else {
            "Dieser Bereich wurde noch nicht geprüft.`nKlicken Sie auf »$($def.Title) prüfen«."
        }
    } else {
        $Script:UI.EmptyHint.Visibility = 'Collapsed'
    }

    # Kacheln (gesamt)
    $open = @($Script:Items | Where-Object { -not $_.IsFixed })
    $counts = @{}
    foreach ($s in 'Kritisch', 'Warnung', 'Info', 'OK') { $counts[$s] = @($open | Where-Object { $_.Severity -eq $s }).Count }
    $Script:UI.CountKritisch.Text = $counts['Kritisch']
    $Script:UI.CountWarnung.Text = $counts['Warnung']
    $Script:UI.CountInfo.Text = $counts['Info']
    $Script:UI.CountOK.Text = $counts['OK']
    if ($Script:Items.Count) {
        $score = [math]::Max(0, 100 - 15 * $counts['Kritisch'] - 5 * $counts['Warnung'])
        $Script:UI.ScoreText.Text = $score
        $Script:UI.ScoreText.Foreground = Get-Brush $(if ($score -ge 80) { '#079455' } elseif ($score -ge 50) { '#DC8A00' } else { '#D92D20' })
    }

    # Zähler in der Navigation (offene Kritisch + Warnung)
    foreach ($cat in 'Fehler', 'Speicher', 'Leistung', 'Akku', 'Software', 'Windows') {
        $catOpen = @($open | Where-Object { $_.Category -eq $cat -and $_.Severity -in 'Kritisch', 'Warnung' })
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
    param([string]$Title, [string]$Text, [string[]]$Labels, [bool]$AllChecked)
    $dlg = [Windows.Markup.XamlReader]::Parse($Script:SelectXaml)
    $dlg.Owner = $Script:Window
    $dlg.Title = $Title
    $dlg.FindName('DlgTitle').Text = $Title
    $dlg.FindName('DlgText').Text = $Text
    $options = New-Object System.Collections.Generic.List[object]
    foreach ($l in $Labels) {
        $o = New-Object LaptopDiagnose.SelectOption
        $o.Label = $l; $o.IsChecked = $AllChecked
        $options.Add($o)
    }
    $dlg.FindName('DlgList').ItemsSource = $options
    $dlg.FindName('DlgAll').Add_Click({ foreach ($o in $options) { $o.IsChecked = $true } }.GetNewClosure())
    $dlg.FindName('DlgNone').Add_Click({ foreach ($o in $options) { $o.IsChecked = $false } }.GetNewClosure())
    $dlg.FindName('DlgOk').Add_Click({ $dlg.DialogResult = $true }.GetNewClosure())
    if (-not $dlg.ShowDialog()) { return $null }
    $idx = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $options.Count; $i++) { if ($options[$i].IsChecked) { $idx.Add($i) } }
    return , $idx.ToArray()
}

#endregion

#region ---------- Aktionen ----------

function Start-Scan {
    param([string[]]$Commands, [string]$Status)
    $code = @'
param($cmds)
if (-not $Script:SystemInfo -or $cmds.Count -gt 1) { $null = Get-SystemOverview }
foreach ($c in $cmds) { & $c }
Get-GuiSnapshot
'@
    $null = Start-WorkerJob -Code $code -Arguments @(, $Commands) -Status $Status -OnDone {
        param($out)
        Update-FromSnapshot (@($out) | Where-Object { $_.IsSnapshot } | Select-Object -Last 1)
        $n = @($Script:Items | Where-Object { $_.CanFix -and $_.Severity -in 'Kritisch', 'Warnung' }).Count
        $Script:UI.StatusText.Text = if ($n) { "Prüfung abgeschlossen – $n Problem(e) können behoben werden." } else { 'Prüfung abgeschlossen.' }
    }
}

function Invoke-SelectedFixes {
    $chosen = @($Script:Items | Where-Object { $_.IsSelected -and $_.CanFix } | Sort-Object Order)
    if (-not $chosen) { return }

    # Teilauswahl (Autostarts, einzelne Updates) abfragen
    $requests = New-Object System.Collections.Generic.List[object]
    $labels = New-Object System.Collections.Generic.List[string]
    foreach ($vm in $chosen) {
        $selection = $null
        if ($vm.SelectLabels.Count -gt 0) {
            $text = switch ($vm.Category) {
                'Leistung' { 'Markieren Sie die Programme, die NICHT mehr automatisch starten sollen. Virenschutz sowie Touchpad-, Audio- und Grafiktreiber-Tools sollten aktiv bleiben. Rückgängig jederzeit im Task-Manager › Autostart.' }
                default { 'Markieren Sie die Updates, die installiert werden sollen.' }
            }
            $selection = Show-SelectionDialog -Title $vm.FixLabel -Text $text -Labels $vm.SelectLabels -AllChecked $vm.SelectAll
            if ($null -eq $selection -or $selection.Count -eq 0) { continue }
            $labels.Add("• $($vm.FixLabel) ($($selection.Count) ausgewählt)")
        } else {
            $labels.Add("• $($vm.FixLabel)")
        }
        $requests.Add(@{ Index = $vm.Index; Selection = $selection })
    }
    if (-not $requests.Count) { return }

    $warn = ''
    if ($chosen | Where-Object { $_.FixLabel -match 'beenden' }) {
        $warn = "`n`nAchtung: Beim Beenden von Programmen gehen ungespeicherte Daten verloren."
    }
    $answer = Show-Message ("Folgende Maßnahmen werden jetzt ausgeführt:`n`n" + ($labels -join "`n") + $warn + "`n`nFortfahren?") 'Probleme beheben' 'Question' 'YesNo'
    if ("$answer" -ne 'Yes') { return }

    $rp = Show-Message "Vor den Änderungen einen Systemwiederherstellungspunkt erstellen?`n(Empfohlen – damit lässt sich der vorherige Zustand wiederherstellen.)" 'Wiederherstellungspunkt' 'Question' 'YesNoCancel'
    if ("$rp" -eq 'Cancel') { return }

    $code = @'
param($requests, $restore)
$list = foreach ($r in $requests) {
    $f = $Script:Findings[$r.Index]
    $f.Selection = $r.Selection
    $f
}
Invoke-FixList -Findings @($list) -RestorePoint:$restore
Get-GuiSnapshot
'@
    $null = Start-WorkerJob -Code $code -Arguments @($requests.ToArray(), ("$rp" -eq 'Yes')) -Status 'Probleme werden behoben …' -OnDone {
        param($out)
        $before = @($Script:Items | Where-Object { $_.IsSelected } | ForEach-Object { $_.Key })
        Update-FromSnapshot (@($out) | Where-Object { $_.IsSnapshot } | Select-Object -Last 1)
        foreach ($it in $Script:Items) { $it.IsSelected = $false }
        $done = @($Script:Items | Where-Object { $_.Key -in $before })
        $ok = @($done | Where-Object { $_.IsFixed }).Count
        $failed = @($done | Where-Object { -not $_.IsFixed -and $_.HasStatus }).Count
        Update-FixButtons
        $msg = "$ok Maßnahme(n) erfolgreich ausgeführt."
        if ($failed) { $msg += "`n$failed Maßnahme(n) fehlgeschlagen – Details in den Ergebniskarten und im Protokoll." }
        $Script:UI.StatusText.Text = $msg -replace "`n", ' '
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
            Start-Process -FilePath $path
        }
    }
}

#endregion

#region ---------- Start ----------

try {
    if (-not (Test-Path -LiteralPath $Script:EnginePath)) { throw "Die Datei LaptopDiagnose.ps1 wurde nicht gefunden ($Script:EnginePath)." }
    if (-not (Test-Path -LiteralPath $BerichtOrdner)) { $null = New-Item -ItemType Directory -Path $BerichtOrdner -Force }
    $Script:LogFile = Join-Path $BerichtOrdner ('Protokoll_GUI_{0:yyyyMMdd_HHmmss}.txt' -f (Get-Date))

    $Script:Window = [Windows.Markup.XamlReader]::Parse($Script:Xaml)
    $Script:UI = @{}
    $names = 'VersionText', 'ChkNurPruefen', 'BtnReport', 'BtnFolder', 'AdminBanner', 'BtnScanPage', 'BtnScanPageText', 'BtnFullScan',
    'PageTitle', 'PageSubtitle', 'ScoreText', 'CountKritisch', 'CountWarnung', 'CountInfo', 'CountOK', 'FindingsScroll', 'SystemCard',
    'SystemList', 'EmptyHint', 'EmptyHintText', 'FindingsList', 'LogBox', 'BtnSelectRecommended', 'BtnClearSelection', 'BtnFix',
    'BtnFixText', 'Busy', 'StatusText',
    'NavAlle', 'NavFehler', 'NavSpeicher', 'NavLeistung', 'NavAkku', 'NavSoftware', 'NavWindows', 'NavLog',
    'BadgeFehler', 'BadgeFehlerText', 'BadgeSpeicher', 'BadgeSpeicherText', 'BadgeLeistung', 'BadgeLeistungText', 'BadgeAkku', 'BadgeAkkuText',
    'BadgeSoftware', 'BadgeSoftwareText', 'BadgeWindows', 'BadgeWindowsText'
    foreach ($n in $names) { $Script:UI[$n] = $Script:Window.FindName($n) }

    $Script:UI.ChkNurPruefen.IsChecked = [bool]$NurPruefen
    if (-not $Script:IsAdmin) { $Script:UI.AdminBanner.Visibility = 'Visible' }

    # Navigation
    foreach ($nav in 'NavAlle', 'NavFehler', 'NavSpeicher', 'NavLeistung', 'NavAkku', 'NavSoftware', 'NavWindows', 'NavLog') {
        $Script:UI[$nav].Add_Checked({
                param($s, $e)
                $Script:Page = [string]$s.Tag
                Update-View
            })
    }

    $Script:UI.BtnFullScan.Add_Click({
            Start-Scan -Commands @('Invoke-ErrorScan', 'Invoke-MemoryScan', 'Invoke-PerformanceScan', 'Invoke-BatteryScan', 'Invoke-SoftwareScan', 'Invoke-WindowsUpdateScan') `
                -Status 'Komplett-Diagnose läuft (je nach System 3–10 Minuten) …'
        })
    $Script:UI.BtnScanPage.Add_Click({
            $def = $Script:Pages[$Script:Page]
            if ($def.Scan) { Start-Scan -Commands @($def.Scan) -Status "$($def.Title) wird geprüft …" }
        })
    $Script:UI.BtnSelectRecommended.Add_Click({
            foreach ($it in $Script:Items) {
                if ($it.CanFix -and $it.Severity -in 'Kritisch', 'Warnung' -and ($Script:Page -in 'Alle', 'Log' -or $it.Category -eq $Script:Page)) { $it.IsSelected = $true }
            }
            Update-FixButtons
        })
    $Script:UI.BtnClearSelection.Add_Click({
            foreach ($it in $Script:Items) { $it.IsSelected = $false }
            Update-FixButtons
        })
    $Script:UI.BtnFix.Add_Click({ Invoke-SelectedFixes })
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
                try { $Script:Job.PS.Stop() } catch { }
            }
            $Script:Timer.Stop()
        })

    $Script:Runspace = New-Worker
    $Script:Window.Add_ContentRendered({
            $init = $Script:WorkerInit + "`n" + '$null = Get-SystemOverview; $Script:ToolVersion; Get-GuiSnapshot'
            $null = Start-WorkerJob -Code $init -Status 'Systeminformationen werden gelesen …' -OnDone {
                param($out)
                $ver = @($out) | Where-Object { $_ -is [string] } | Select-Object -First 1
                if ($ver) { $Script:UI.VersionText.Text = "& Reparatur  ·  v$ver" }
                Update-FromSnapshot (@($out) | Where-Object { $_.IsSnapshot } | Select-Object -Last 1)
            }
        })

    Update-View
    $Script:Timer.Start()
    $null = $Script:Window.ShowDialog()
} catch {
    $msg = $_.Exception.Message
    try { $null = [System.Windows.MessageBox]::Show("Die Oberfläche konnte nicht gestartet werden:`n`n$msg", 'Laptop-Diagnose', 'OK', 'Error') }
    catch { Write-Host "Fehler: $msg" -ForegroundColor Red }
} finally {
    if ($Script:Runspace) { try { $Script:Runspace.Close(); $Script:Runspace.Dispose() } catch { } }
}

#endregion
