# MySQL/MariaDB skip replication errors
Skip Last_SQL_Error of your slave so replication continues

Sometimes replication on the slave stops due to error(s) and they're printed out in `Last_SQL_Error`  
These errors can be viewed by either using this query:
````
SHOW SLAVE STATUS \G;
````
Or in the terminal like so:  
````
sudo mysql -e "SHOW SLAVE STATUS\G" 
````

This script handles two error codes, `1032` and `1062`

![MySQL-MariaDB-skip-replication-errors](https://github.com/spithash/MySQL-MariaDB-skip-replication-errors/assets/3981730/d49a7339-5197-41cc-a456-3cc84912462f)

### Error Code 1032: Can't find record in 'table_name'

This error occurs when a replication slave attempts to execute a statement that affects a row that does not exist on the slave. This is typically a problem with DELETE or UPDATE statements. In a replication setup, this usually indicates a discrepancy between the master and the slave databases.  
**Common Causes:**
        Data inconsistency between master and slave due to missed transactions.
        Manual changes to the data on the slave that were not replicated from the master.
        Network issues causing loss of replication data.

### Error Code 1062: Duplicate entry 'key_value' for key 'PRIMARY'

This error occurs when a replication slave tries to insert a row with a primary key that already exists in the table. This typically happens with INSERT or INSERT ... ON DUPLICATE KEY UPDATE statements.  

**Common Causes:** Data duplication due to re-running transactions or inserting data manually on the slave. The same row being inserted on both the master and slave independently. Incorrect or incomplete handling of unique constraints during data replication.

# Skipping errors
These errors can be skipped with:
````
SET GLOBAL SQL_SLAVE_SKIP_COUNTER = 1;
````
Number 1 means skip/ignore one error at a time. This value can be increased.  
Official mysql documentation:
>This statement skips the next N events from the master. This is useful for recovering from replication stops caused by a statement.  
>This statement is valid only when the slave threads are not running. Otherwise, it produces an error.  
>When using this statement, it is important to understand that the binary log is actually organized as a sequence of groups known as event groups. Each event group consists of a sequence of events.  

### Why These Errors Occur in Replication

**Data Inconsistency:** These errors often arise from data inconsistencies between the master and the slave. If the data on the slave is not an exact copy of the master, operations like updates and deletions can fail.  
**Manual Interventions:** Manual updates or deletions on the slave can lead to these errors if those changes are not reflected on the master.  
**Network Issues:** Intermittent network issues can cause the slave to miss some of the replication events from the master, leading to inconsistencies.  

## Using
Run the script as `sudo` (assuming root can connect locally). There are cases where mariadb and/or mysql commands are not available to users with no super user privileges (sudoers).  
Otherwise, use something like `.my.cnf` in your home folder.
````
sudo bash mysql-mariadb-skip-errors.sh
````
OR
````
sudo bash forloop.sh
````
