#!/bin/bash

# Define color codes
RED='\033[1;31m'        # Bold red
GREEN='\033[1;32m'      # Bold green
YELLOW='\033[1;33m'     # Bold yellow
CYAN='\033[1;36m'       # Bold cyan
WHITE_BOLD='\033[1;37m' # Bold white
NC='\033[0m'            # No Color

# Check if mariadb command exists, otherwise use mysql
if command -v mariadb &> /dev/null; then
  MYSQL_CMD="mariadb"
else
  MYSQL_CMD="mysql"
fi

# Initialize counters
ERROR_1032_COUNT=0
ERROR_1062_COUNT=0

while true; do
  echo -e "${CYAN}Checking MySQL slave status...${NC}"
  SLAVE_STATUS=$($MYSQL_CMD -e "SHOW SLAVE STATUS\G")

  # Display output after 'Slave_SQL_Running_State:'
  SLAVE_SQL_RUNNING_STATE=$(echo "$SLAVE_STATUS" | awk '/Slave_SQL_Running_State:/ {print substr($0, index($0,$2))}')
  echo -e "${YELLOW}${SLAVE_SQL_RUNNING_STATE}${NC}"

  LAST_SQL_ERROR=$(echo "$SLAVE_STATUS" | grep "Last_SQL_Error:" | sed 's/^[ \t]*//;s/[ \t]*$//' | tr -d '\n')
  EXEC_MASTER_LOG_POS=$(echo "$SLAVE_STATUS" | grep "Exec_Master_Log_Pos:" | awk '{print $2}')
  LAST_SQL_ERRNO=$(echo "$SLAVE_STATUS" | grep "Last_SQL_Errno:" | awk '{print $2}')

  echo -e "${YELLOW}${LAST_SQL_ERROR}${NC}"
  echo -e "${YELLOW}Exec_Master_Log_Pos: $EXEC_MASTER_LOG_POS${NC}"

  if [[ "$LAST_SQL_ERRNO" == "0" ]]; then
    echo -e "${WHITE_BOLD}(replication seems to be working)${NC}"
  fi

  if [[ $(echo "$LAST_SQL_ERROR" | grep -c -E "Error_code: 1032|Error_code: 1062") -gt 0 ]]; then
    # Determine the error code
    ERROR_CODE=$(echo "$LAST_SQL_ERROR" | grep -oE "Error_code: [0-9]+" | cut -d' ' -f2)

    echo -e "${RED}Error detected at Exec_Master_Log_Pos: $EXEC_MASTER_LOG_POS. Skipping problematic transaction...${NC}"
    $MYSQL_CMD -e "STOP SLAVE; SET GLOBAL SQL_SLAVE_SKIP_COUNTER = 1; START SLAVE;"
    sleep 2
    NEW_SLAVE_STATUS=$($MYSQL_CMD -e "SHOW SLAVE STATUS\G")
    NEW_EXEC_MASTER_LOG_POS=$(echo "$NEW_SLAVE_STATUS" | grep "Exec_Master_Log_Pos:" | awk '{print $2}')
    echo -e "${GREEN}✓ Skipped one transaction. New Exec_Master_Log_Pos: $NEW_EXEC_MASTER_LOG_POS${NC}"

    # Increment the respective error code count
    if [[ "$ERROR_CODE" == "1032" ]]; then
      ((ERROR_1032_COUNT++))
    elif [[ "$ERROR_CODE" == "1062" ]]; then
      ((ERROR_1062_COUNT++))
    fi

    if [[ "$NEW_EXEC_MASTER_LOG_POS" == "$EXEC_MASTER_LOG_POS" ]]; then
      echo -e "${RED}Error: Exec_Master_Log_Pos did not change. Exiting...${NC}"
      echo -e "${RED}✗ Script failed.${NC}"
      exit 1
    fi
  else
    echo -e "${GREEN}✓ No relevant error found. Exiting...${NC}"
    break
  fi
  sleep 1

done

sleep 1

# Display the error report if there are errors detected
if [[ "$ERROR_1032_COUNT" -ne 0 || "$ERROR_1062_COUNT" -ne 0 ]]; then
  echo -e "${CYAN}Error Report:${NC}"
  echo -e "${YELLOW}Skipped ${ERROR_1032_COUNT} transactions with error code 1032${NC}"
  echo -e "${YELLOW}Skipped ${ERROR_1062_COUNT} transactions with error code 1062${NC}"
fi
