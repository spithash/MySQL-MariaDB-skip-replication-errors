#!/bin/bash

# Define color codes
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE_BOLD='\033[1;37m'
NC='\033[0m'

# Check if mariadb command exists, otherwise use mysql
if command -v mariadb &>/dev/null; then
  MYSQL_CMD="mariadb"
else
  MYSQL_CMD="mysql"
fi

# Initialize counters
ERROR_1032_COUNT=0
ERROR_1062_COUNT=0

while true; do
  echo -e "${CYAN}Checking MySQL slave status...${NC}"
  SLAVE_STATUS=$("$MYSQL_CMD" -e "SHOW ALL SLAVES STATUS\G")

  SLAVE_SQL_RUNNING_STATE=$(echo "$SLAVE_STATUS" | awk '/Slave_SQL_Running_State:/ {print substr($0, index($0,$2))}')
  LAST_SQL_ERROR=$(echo "$SLAVE_STATUS" | grep "Last_SQL_Error:" | sed 's/^[ \t]*//;s/[ \t]*$//' | tr -d '\n')
  EXEC_MASTER_LOG_POS=$(echo "$SLAVE_STATUS" | grep "Exec_Master_Log_Pos:" | awk '{print $2}')
  LAST_SQL_ERRNO=$(echo "$SLAVE_STATUS" | grep "Last_SQL_Errno:" | awk '{print $2}')

  echo -e "${YELLOW}Slave_SQL_Running_State: ${SLAVE_SQL_RUNNING_STATE}${NC}"
  echo -e "${YELLOW}${LAST_SQL_ERROR}${NC}"
  echo -e "${YELLOW}Exec_Master_Log_Pos: $EXEC_MASTER_LOG_POS${NC}"

  if [[ "$LAST_SQL_ERRNO" == "0" ]]; then
    echo -e "${WHITE_BOLD}(Replication seems to be working)${NC}"
    break
  fi

  if [[ "$LAST_SQL_ERRNO" == "1032" || "$LAST_SQL_ERRNO" == "1062" ]]; then
    echo -e "${RED}Error detected at Exec_Master_Log_Pos: $EXEC_MASTER_LOG_POS. Skipping problematic transaction...${NC}"
    
    # Stop slave and skip transaction
    "$MYSQL_CMD" -e "STOP SLAVE;"
    "$MYSQL_CMD" -e "SET GLOBAL SQL_SLAVE_SKIP_COUNTER = 1;"
    "$MYSQL_CMD" -e "START SLAVE;"
    sleep 1
    
    # Verify slave status
    NEW_SLAVE_STATUS=$("$MYSQL_CMD" -e "SHOW ALL SLAVES STATUS\G")
    NEW_EXEC_MASTER_LOG_POS=$(echo "$NEW_SLAVE_STATUS" | grep "Exec_Master_Log_Pos:" | awk '{print $2}')
    echo -e "${GREEN}✓ Skipped one transaction. New Exec_Master_Log_Pos: $NEW_EXEC_MASTER_LOG_POS${NC}"

    # Increment error counters
    if [[ "$LAST_SQL_ERRNO" == "1032" ]]; then
      ((ERROR_1032_COUNT++))
    elif [[ "$LAST_SQL_ERRNO" == "1062" ]]; then
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

if [[ "$ERROR_1032_COUNT" -ne 0 || "$ERROR_1062_COUNT" -ne 0 ]]; then
  echo -e "${CYAN}Error Report:${NC}"
  echo -e "${YELLOW}Skipped ${ERROR_1032_COUNT} transactions with error code 1032${NC}"
  echo -e "${YELLOW}Skipped ${ERROR_1062_COUNT} transactions with error code 1062${NC}"
fi

exit
