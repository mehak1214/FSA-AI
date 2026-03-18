# Removing Record Type Assignments from Profiles

This guide explains how to remove record type assignments for specific record types from all profiles in a Salesforce org.

## Overview

Based on your request, we need to remove assignments for the following record types from all profiles:
- PMT Project (DeveloperName: PMT_Project)
- SFS Case (DeveloperName: SDO_SFS_Case) 
- test (DeveloperName: test)

## Prerequisites

1. Salesforce CLI installed and configured
2. Access to the target org
3. Profile metadata retrieved from the org

## Steps to Remove Record Type Assignments

### Step 1: Retrieve Profile Metadata

First, retrieve the profile metadata from your org:

```bash
sf project retrieve start --metadata "Profile" --target-org "YOUR_ORG_ALIAS"
```

### Step 2: Prepare the Environment

Ensure the profile files are located in:
```
force-app/main/default/profiles/
```

### Step 3: Run the Removal Script

Use the PowerShell script provided:

```powershell
.\remove-record-type-assignments.ps1
```

### Step 4: Deploy Changes

Deploy the updated profile metadata back to the org:

```bash
sf project deploy start --target-org "YOUR_ORG_ALIAS"
```

## How the Script Works

The PowerShell script:
1. Identifies all `.profile-meta.xml` files in the profiles directory
2. For each profile, searches for record type visibility blocks matching the specified record types
3. Removes the entire `<recordTypeVisibilities>` block for each matching record type
4. Saves the updated profile files

## Sample Profile Structure

Here's an example of what a profile file looks like before modification:

```xml
<Profile xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>SampleProfile</fullName>
    <recordTypeVisibilities>
        <recordType>Case.PMT_Project</recordType>
        <visible>true</visible>
        <default>false</default>
    </recordTypeVisibilities>
    <recordTypeVisibilities>
        <recordType>Case.SDO_SFS_Case</recordType>
        <visible>true</visible>
        <default>false</default>
    </recordTypeVisibilities>
    <recordTypeVisibilities>
        <recordType>Case.test</recordType>
        <visible>true</visible>
        <default>false</default>
    </recordTypeVisibilities>
</Profile>
```

After running the script, the matching record type visibility blocks will be removed.

## Important Notes

1. Always backup your profile metadata before making changes
2. Test the changes in a sandbox environment first
3. The script removes the entire record type visibility block, not just the assignment
4. Make sure to use the correct org alias when deploying
5. Some profiles may not have these record type assignments, and that's fine

## Troubleshooting

If you encounter issues:
1. Verify the profiles directory exists and contains `.profile-meta.xml` files
2. Check that the record type DeveloperNames are correct
3. Ensure you have proper permissions to deploy profile metadata
4. Confirm your org connection is active with `sf org list`