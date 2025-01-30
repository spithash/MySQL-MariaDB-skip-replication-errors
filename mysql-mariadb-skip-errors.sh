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

echo -e "${CYAN}Checking MySQL slave status...${NC}"

while true; do
  # Fetch slave status
  SLAVE_STATUS=$("$MYSQL_CMD" -e "SHOW ALL SLAVES STATUS\G")

  # Get slave start positions
  SLAVE_ENTRIES=$(echo "$SLAVE_STATUS" | awk '/^\*+/ {print NR}')
  SLAVE_ROWS=($SLAVE_ENTRIES)
  SLAVE_COUNT=${#SLAVE_ROWS[@]}

  if [ "$SLAVE_COUNT" -eq 0 ]; then
    echo -e "${RED}No slave entries found.${NC}"
    break
  fi

  # Process each slave individually
  for ((i = 0; i < SLAVE_COUNT; i++)); do
    # Extract individual slave status
    if [ $((i + 1)) -lt "$SLAVE_COUNT" ]; then
      SLAVE_ROW=$(echo "$SLAVE_STATUS" | sed -n "${SLAVE_ROWS[i]},$((${SLAVE_ROWS[i + 1]} - 1))p")
    else
      SLAVE_ROW=$(echo "$SLAVE_STATUS" | sed -n "${SLAVE_ROWS[i]},\$p")
    fi

    # Extract relevant fields
    SLAVE_SQL_RUNNING_STATE=$(echo "$SLAVE_ROW" | awk -F': ' '/Slave_SQL_Running_State:/ {print $2}')
    LAST_SQL_ERROR=$(echo "$SLAVE_ROW" | awk -F': ' '/Last_SQL_Error:/ {print $2}')
    EXEC_MASTER_LOG_POS=$(echo "$SLAVE_ROW" | awk -F': ' '/Exec_Master_Log_Pos:/ {print $2}')
    LAST_SQL_ERRNO=$(echo "$SLAVE_ROW" | awk -F': ' '/Last_SQL_Errno:/ {print $2}')

    # Display slave status
    echo -e "${YELLOW}Slave_SQL_Running_State: ${SLAVE_SQL_RUNNING_STATE}${NC}"
    echo -e "${YELLOW}Exec_Master_Log_Pos: $EXEC_MASTER_LOG_POS${NC}"

    if [[ -z "$LAST_SQL_ERRNO" || "$LAST_SQL_ERRNO" == "0" ]]; then
      echo -e "${WHITE_BOLD}(Replication for this slave seems to be working)${NC}"
      continue
    fi

    if [[ "$LAST_SQL_ERRNO" == "1032" || "$LAST_SQL_ERRNO" == "1062" ]]; then
      echo -e "${RED}Error $LAST_SQL_ERRNO detected at Exec_Master_Log_Pos: $EXEC_MASTER_LOG_POS. Skipping transaction...${NC}"

      # Stop slave and skip transaction
      "$MYSQL_CMD" -e "STOP SLAVE;"
      "$MYSQL_CMD" -e "SET GLOBAL SQL_SLAVE_SKIP_COUNTER = 1;"
      "$MYSQL_CMD" -e "START SLAVE;"
      sleep 1

      # Verify if skipping worked
      NEW_SLAVE_STATUS=$("$MYSQL_CMD" -e "SHOW ALL SLAVES STATUS\G")
      NEW_EXEC_MASTER_LOG_POS=$(echo "$NEW_SLAVE_STATUS" | awk -F': ' '/Exec_Master_Log_Pos:/ {print $2}')

      if [[ "$NEW_EXEC_MASTER_LOG_POS" == "$EXEC_MASTER_LOG_POS" ]]; then
        echo -e "${RED}Error: Exec_Master_Log_Pos did not change. Exiting...${NC}"
        exit 1
      fi

      # Increment counters
      [[ "$LAST_SQL_ERRNO" == "1032" ]] && ((ERROR_1032_COUNT++))
      [[ "$LAST_SQL_ERRNO" == "1062" ]] && ((ERROR_1062_COUNT++))

      echo -e "${GREEN}✓ Transaction skipped. New Exec_Master_Log_Pos: $NEW_EXEC_MASTER_LOG_POS${NC}"
    else
      echo -e "${GREEN}✓ No critical error found for this slave. Moving to the next...${NC}"
    fi
  done

  break
done

# Final report
echo -e "${CYAN}Error Report:${NC}"
echo -e "${YELLOW}Skipped ${ERROR_1032_COUNT} transactions with error code 1032${NC}"
echo -e "${YELLOW}Skipped ${ERROR_1062_COUNT} transactions with error code 1062${NC}"

exit 0
