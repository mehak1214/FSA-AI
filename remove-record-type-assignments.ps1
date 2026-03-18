# PowerShell script to remove specific record type assignments from specific profiles
# This script should be run after retrieving profile metadata from the org

# Define the record types to remove (using DeveloperNames)
$recordTypesToRemove = @("PMT_Project", "SDO_SFS_Case", "test")

# Define the specific profiles to target
$targetProfiles = @(
    "Chatter External User.profile-meta.xml",
    "Chatter Free User.profile-meta.xml", 
    "Chatter Moderator User.profile-meta.xml",
    "Platform Integration User.profile-meta.xml",
    "Content Only User.profile-meta.xml",
    "Database.com Light User.profile-meta.xml",
    "Database.com User.profile-meta.xml",
    "Field Service Optimization.profile-meta.xml",
    "Force.com - Free User.profile-meta.xml",
    "Minimum Access - API Only Integrations.profile-meta.xml",
    "Standard Platform One App User.profile-meta.xml",
    "Siteforce Only User.profile-meta.xml"
)

# Get the path to the profiles directory
$profilesPath = "force-app\main\default\profiles"

# Check if profiles directory exists
if (!(Test-Path $profilesPath)) {
    Write-Host "Error: Profiles directory not found at: $profilesPath" -ForegroundColor Red
    Write-Host "Please ensure you have retrieved profile metadata from the org first." -ForegroundColor Red
    exit 1
}

Write-Host "Starting to process profiles in: $profilesPath" -ForegroundColor Yellow

# Process each profile file
$profileFiles = Get-ChildItem -Path $profilesPath -Filter "*.profile-meta.xml"
if ($profileFiles.Count -eq 0) {
    Write-Host "No profile files found in the directory." -ForegroundColor Yellow
    exit 0
}

$profilesProcessed = 0
$profilesModified = 0

foreach ($profileFile in $profileFiles) {
    # Check if this profile is in our target list
    $isTargetProfile = $targetProfiles -contains $profileFile.Name
    
    Write-Host "Processing profile: $($profileFile.Name)" -ForegroundColor Cyan
    
    try {
        # Read the profile file content
        $content = Get-Content $profileFile.FullName -Raw
        
        $originalContent = $content
        $changesMade = $false
        
        # Only process if this is a target profile
        if ($isTargetProfile) {
            # For each record type to remove, find and remove the record type visibility section
            foreach ($recordType in $recordTypesToRemove) {
                # Pattern to match the entire recordTypeVisibilities block for this record type
                # This pattern looks for the specific record type within a recordTypeVisibilities block
                $pattern = "(<recordTypeVisibilities>[\s\S]*?<recordType>Case\.$recordType</recordType>[\s\S]*?</recordTypeVisibilities>)"
                
                if ($content -match $pattern) {
                    Write-Host "  Removing record type assignment for: $recordType" -ForegroundColor Green
                    $content = $content -replace $pattern, ""
                    $changesMade = $true
                }
            }
        } else {
            Write-Host "  Skipping non-target profile: $($profileFile.Name)" -ForegroundColor Gray
        }
        
        # If changes were made, write the updated content back to the file
        if ($changesMade) {
            Set-Content $profileFile.FullName $content
            Write-Host "  Updated profile: $($profileFile.Name)" -ForegroundColor Green
            $profilesModified++
        } elseif ($isTargetProfile) {
            Write-Host "  No changes needed for: $($profileFile.Name)" -ForegroundColor Gray
        }
        $profilesProcessed++
        
    } catch {
        Write-Host "  Error processing $($profileFile.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Finished processing $profilesProcessed profiles." -ForegroundColor Yellow
Write-Host "Modified $profilesModified profiles." -ForegroundColor Green
Write-Host "Note: Remember to deploy these changes to your org using 'sf project deploy start'." -ForegroundColor Yellow
