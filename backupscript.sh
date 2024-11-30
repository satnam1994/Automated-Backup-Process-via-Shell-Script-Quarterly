#!/bin/bash

# Load environment variables from .env file
PATH=.env

source .env
artisan=/var/www/html/artisan

# Set up date variable for naming backup files
DATE=$(date +"%Y%m%d")
BACKUP_FILE="${EXPORT_DIR}/backup_${DB_DATABASE}_${DATE}.sql"
COMPRESSED_FILE="${EXPORT_DIR}/backup_${DB_DATABASE}_${DATE}.zip"
THREE_MONTHS_AGO=$(date -d "-3 months" +"%Y-%m-%d")

# Function to send email notifications using msmtp
send_email() {
    # Decrypt the mail password
    MAIL_PASSWORD=$(php $artisan tinker --execute="echo Crypt::decrypt(env('MAIL_PASSWORD'));")
    local subject="$1"
    local message="$2"
    echo -e "Subject: $subject\nFrom: $MAIL_FROM_ADDRESS\nTo: $backup_status_email\n\n$message" | \
    msmtp --host="$MAIL_HOST" --port="$MAIL_PORT" --auth=on --user="$MAIL_USERNAME" --passwordeval="echo $MAIL_PASSWORD" --tls=on -f "$MAIL_FROM_ADDRESS" "$backup_status_email"
}

# Retry function
retry_command() {
    local retries=3
    local count=0
    until [ "$count" -ge "$retries" ]
    do
        "$@" && break  # Run the command
        count=$((count+1))
        echo "Retry $count/$retries for $@ failed. Retrying..."
        sleep 5  # Wait before retrying
    done

    if [ "$count" -ge "$retries" ]; then
        echo "Failed after $retries attempts for command: $@"
        send_email "Backup Failure: Command Error" "The command '$@' failed after $retries attempts. Please check logs for more details."
        exit 1
    fi
}

# Step 1: Check if export directory exists, create it if it does not
if [ ! -d "$EXPORT_DIR" ]; then
    echo "Export directory does not exist. Creating directory: $EXPORT_DIR"
    mkdir -p "$EXPORT_DIR"
    if [ $? -ne 0 ]; then
        echo "Failed to create export directory $EXPORT_DIR. Exiting."
        send_email "Backup Failure: Directory Creation Error" "Failed to create the export directory '$EXPORT_DIR'. Please check permissions."
        exit 1
    fi
    echo "Export directory created successfully."
else
    echo "Export directory exists: $EXPORT_DIR"
fi

# Step 2: Check for the last backup
last_backup_file=$(ls -t ${EXPORT_DIR}/backup_${DB_DATABASE}_*.zip 2>/dev/null | head -n 1)

if [ -z "$last_backup_file" ]; then
    echo "No previous backup found. A new backup will be created."
else
    last_backup_date=$(stat -c %Y "$last_backup_file") # Get last backup modification time
    last_backup_date=$(date -d @"$last_backup_date" +"%Y-%m-%d")
    last_backup_date=2024-07-09


    #echo "$last_backup_date"
    #exit 1

    # Compare the last backup date with three months ago
    if [[ "$last_backup_date" < "$THREE_MONTHS_AGO" ]]; then
        echo "Last backup is older than 3 months. A new backup will be created."
    else
        echo "Last backup is still valid. No new backup needed."
        exit 0 # Exit if no new backup is needed
    fi
fi

# Decrypt the database password
DB_PASSWORD=$(php $artisan tinker --execute="echo Crypt::decrypt(env('DB_PASSWORD'));")

# List of tables to back up and delete from
declare -a tables=("vehicle_trips" "lpr_logs" "vehicle_register_api_logs" "trip_register_api_logs" "mis_trip_data_logs" "driver_register_api_logs" "device_health_logs" "rfid_logs" "rfid_error_logs" "rfid_lpr_logs" "flag_reports" "flag_histories" "anpr_error_logs")

# Step 3: Create an SQL backup for each table
echo "Creating SQL backup for records older than 3 months..."

backup_tables=()
for table in "${tables[@]}"; do
    if mysql -u $DB_USERNAME -p"$DB_PASSWORD" -h $DB_HOST -P $DB_PORT -e "USE $DB_DATABASE; SHOW TABLES LIKE '$table';" | grep -q "$table"; then
        backup_tables+=("$table")
    else
        echo "Table '$table' does not exist. Skipping."
    fi
done

if [ ${#backup_tables[@]} -gt 0 ]; then
    retry_command mysqldump -u $DB_USERNAME -p"$DB_PASSWORD" $DB_DATABASE ${backup_tables[@]} --where="created_at < '$THREE_MONTHS_AGO'" > $BACKUP_FILE
    echo "SQL backup created successfully."
else
    echo "No tables to back up."
    exit 0
fi

# Step 4: Compress the backup file
echo "Compressing backup file..."
retry_command zip $COMPRESSED_FILE $BACKUP_FILE
echo "Backup file compressed successfully."

# Step 5: Upload the compressed file to Google Drive using the Google Drive API
echo "Uploading backup to Google Drive..."
UPLOAD_SUCCESS=0  # Set to 0 initially to indicate failure

# Python script to handle the upload
python3.11 << END
import os
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

def upload_to_drive():
    try:
        # Load Google credentials
        credentials = service_account.Credentials.from_service_account_file('$GOOGLE_CREDENTIALS')
        drive_service = build('drive', 'v3', credentials=credentials)

        # Define metadata and file to upload
        file_metadata = {
            'name': os.path.basename('$COMPRESSED_FILE'),
            'parents': ['$GOOGLE_FOLDER_ID']
        }

        media = MediaFileUpload('$COMPRESSED_FILE', mimetype='application/zip')

        # Upload the file to Google Drive
        file = drive_service.files().create(body=file_metadata, media_body=media, fields='id').execute()

        # Check if 'id' is in the response to confirm success
        if 'id' in file:
            print(f"File uploaded successfully. File ID: {file.get('id')}")
            exit(0)  # Exit with success status
        else:
            print("File upload failed. No file ID returned.")
            exit(1)  # Exit with failure status

    except Exception as e:
        print(f"Error uploading file: {str(e)}")
        exit(1)  # Exit with failure status

upload_to_drive()
END

# Check the exit status of the Python script
if [ $? -eq 0 ]; then
    echo "File uploaded to Google Drive successfully."
    UPLOAD_SUCCESS=1
else
    echo "Failed to upload backup to Google Drive. Deleting newly generated backup files."
    rm -f $BACKUP_FILE $COMPRESSED_FILE
    send_email "Backup Failure: Upload Error" "Failed to upload the backup file to Google Drive. The backup file '$COMPRESSED_FILE' has been deleted."
    exit 1
fi

# Step 6: Delete records older than 3 months from the database
echo "Deleting records older than 3 months from the database..."
for table in "${backup_tables[@]}"; do
    echo "Deleting from table $table..."
    retry_command mysql -u $DB_USERNAME -p"$DB_PASSWORD" -h $DB_HOST -P $DB_PORT -e "DELETE FROM $DB_DATABASE.$table WHERE created_at < '$THREE_MONTHS_AGO';"
done

# Step 7: Clean up old local backups only if the upload was successful
if [ $UPLOAD_SUCCESS -eq 1 ]; then
    echo "Cleaning up old local backups..."
    retry_command find $EXPORT_DIR -type f -name "*.zip" -mtime +7 -exec rm {} \;
    retry_command find $EXPORT_DIR -type f -name "*.sql" -mtime +7 -exec rm {} \;
fi

# Sending success email only if the upload is successful
if [ $UPLOAD_SUCCESS -eq 1 ]; then
    send_email "Backup and Upload Successful" "Backup and upload completed successfully for database '$DB_DATABASE' on $(date +"%A %d %B %Y %I:%M:%S %p %Z"). The backup file is located at '$COMPRESSED_FILE'."
    echo "Backup, upload, and cleanup completed."
else
    send_email "Backup Failure: Cleanup Error" "Backup upload failed, and the backup file '$COMPRESSED_FILE' was not deleted. Please check logs for further details."
fi

