# PE DISM Tool Implementation

I'll create a complete PowerShell-based application with WPF for the GUI according to your specification. Here's the full implementation:

```powershell
#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    PE DISM Tool - A tool for quick customization of Windows PE
.DESCRIPTION
    This PowerShell application provides a GUI for mounting and unmounting WIM files
    using DISM commands, primarily focused on Windows PE customization.
.NOTES
    Author: Based on specification by Kevin Kaminski MVP
    License: MIT
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# Define the XAML for the WPF UI
[xml]$xaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="PE DISM Tool" Height="500" Width="700" 
    WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" Text="PE DISM Tool" FontSize="20" FontWeight="Bold" Margin="0,0,0,15"/>
        
        <!-- WIM File Selection -->
        <GroupBox Grid.Row="1" Header="WIM File Selection" Margin="0,5,0,5" Padding="5">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <TextBox Grid.Row="0" Grid.Column="0" x:Name="txtWimFile" Margin="0,5,5,5" Padding="5" 
                         Text="C:\osdcloud\testosd\media\sources\boot.wim"/>
                <Button Grid.Row="0" Grid.Column="1" x:Name="btnBrowseWim" Content="Browse..." Margin="0,5,0,5" Padding="10,5"/>
                
                <StackPanel Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="0,5,0,5">
                    <TextBlock Text="Index:" VerticalAlignment="Center" Margin="0,0,10,0"/>
                    <ComboBox x:Name="cmbIndex" Width="100" SelectedIndex="0">
                        <ComboBoxItem Content="1"/>
                        <ComboBoxItem Content="2"/>
                    </ComboBox>
                </StackPanel>
            </Grid>
        </GroupBox>
        
        <!-- Mount Directory -->
        <GroupBox Grid.Row="2" Header="Mount Directory" Margin="0,5,0,5" Padding="5">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                
                <TextBox Grid.Column="0" x:Name="txtMountDir" Margin="0,5,5,5" Padding="5" Text="C:\WinPE\mount"/>
                <Button Grid.Column="1" x:Name="btnBrowseMount" Content="Browse..." Margin="0,5,0,5" Padding="10,5"/>
            </Grid>
        </GroupBox>
        
        <!-- Action Buttons -->
        <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,10,0,10" HorizontalAlignment="Center">
            <Button x:Name="btnMount" Content="Mount WIM" Padding="20,10" Margin="0,0,20,0" FontSize="14"/>
            <Button x:Name="btnUnmount" Content="Unmount WIM" Padding="20,10" Margin="20,0,0,0" FontSize="14"/>
        </StackPanel>
        
        <!-- Progress Bar -->
        <ProgressBar Grid.Row="4" x:Name="progressBar" Height="20" Margin="0,5,0,5"/>
        
        <!-- Status and Error Output -->
        <GroupBox Grid.Row="5" Header="Status and Output" Margin="0,5,0,5">
            <TextBox x:Name="txtOutput" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" 
                     HorizontalScrollBarVisibility="Auto" FontFamily="Consolas"/>
        </GroupBox>
        
        <!-- Status Bar -->
        <StatusBar Grid.Row="6" Height="25">
            <StatusBarItem>
                <TextBlock x:Name="txtStatus" Text="Ready"/>
            </StatusBarItem>
        </StatusBar>
    </Grid>
</Window>
"@

# Create a form object from the XAML
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Initialize logging
$logFolder = "$env:USERPROFILE\PEDismTool\Logs"
$logFile = "$logFolder\PEDismTool_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    # Create log directory if it doesn't exist
    if (-not (Test-Path -Path $logFolder)) {
        New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    Add-Content -Path $logFile -Value $logEntry
    
    # Update UI
    $txtOutput = $window.FindName('txtOutput')
    $txtOutput.AppendText("$logEntry`r`n")
    $txtOutput.ScrollToEnd()
    
    # Update status bar for important messages
    if ($Level -ne 'INFO') {
        $txtStatus = $window.FindName('txtStatus')
        $txtStatus.Text = $Message
    }
}

function Test-AdminPrivileges {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-Application {
    # Check for admin privileges
    if (-not (Test-AdminPrivileges)) {
        [System.Windows.MessageBox]::Show("This application requires administrator privileges to run.", "Administrator Required", 
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        $window.Close()
        exit
    }
    
    # Check for DISM availability
    try {
        $dismVersion = & dism /? | Select-String -Pattern "Version:" | ForEach-Object { $_.ToString().Trim() }
        Write-Log "DISM $dismVersion detected"
    }
    catch {
        Write-Log "DISM tool not found or not accessible" -Level ERROR
        [System.Windows.MessageBox]::Show("DISM tool not foun