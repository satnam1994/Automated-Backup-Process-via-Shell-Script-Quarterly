FLow Structure

<img src="https://github.com/satnam1994/Automated-Backup-Process-via-Shell-Script-Quarterly/blob/main/basic_backup.drawio.png">

README for Database Backup Script
Overview
This script is designed to automate the backup, compression, and upload process for a database. It includes several key features, such as:

Backup Creation: Exports records older than 3 months from specific database tables.
Compression: Compresses the exported SQL files into a ZIP file.
Upload: Uploads the compressed backup to Google Drive.
Database Cleanup: Deletes records older than 3 months from the database after successful upload.
Email Notifications: Sends email alerts for success or failure events.
Retry Mechanism: Retries failed commands up to three times.
Requirements
System
Ubuntu/Linux OS
Bash Shell
MySQL/MariaDB
Python 3.11
Google Drive API credentials
msmtp (for email notifications)
Software Dependencies
MySQL client for database interactions
Zip utility for file compression
Python libraries:
google-api-python-client
google-auth
Setup
Environment Variables

Create a .env file and define the following variables:
DB_HOST=
DB_PORT=
DB_USERNAME=
DB_PASSWORD=
DB_DATABASE=
EXPORT_DIR=
MAIL_HOST=
MAIL_PORT=
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_FROM_ADDRESS=
GOOGLE_CREDENTIALS=
GOOGLE_FOLDER_ID=
backup_status_email=
Ensure the .env file is in the script's working directory.
Install Required Software

sudo apt update
sudo apt install mysql-client zip python3.11 python3-pip
pip install google-api-python-client google-auth
Google Drive API Setup

Obtain a service account JSON credentials file from Google Cloud Console.
Save it to a secure location and reference it in the GOOGLE_CREDENTIALS variable.
msmtp Setup

Configure msmtp to enable email notifications. Add your mail server credentials in the .env file.
Grant Execution Permissions

chmod +x backup_script.sh
Usage
Place the script in your preferred directory.
Run the script:
./backup_script.sh
Features
Backup Creation
Exports data from specific tables older than 3 months.
Automatically checks if tables exist before proceeding.
Compression
Compresses SQL backup files into a ZIP format for efficient storage.
Upload to Google Drive
Uses the Google Drive API to upload compressed backups.
Ensures security by utilizing a service account.
Cleanup
Deletes old backups (older than 7 days) from the local directory after successful upload.
Removes records older than 3 months from the database.
Email Notifications
Sends email updates for the following events:
Successful backup and upload.
Failure during any step (backup, compression, upload, or cleanup).
Retry Mechanism
Commands are retried up to three times in case of failure.
Example Workflow
Check for the last backup:
If a backup exists and is less than 3 months old, no new backup is created.
Decrypt sensitive credentials (e.g., database password).
Generate backups for specified tables.
Compress and upload the backup to Google Drive.
Remove records older than 3 months from the database.
Send email notifications summarizing the process.
Error Handling
If any step fails, the script:
Stops further execution.
Sends an email notification detailing the failure.
Deletes partially created backup files to maintain consistency.
Logs
Outputs progress logs and errors to the console for transparency and troubleshooting.
This script is basically designed for the laravel application.
