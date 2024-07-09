#!/bin/bash

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

while true; do
  echo -e "${CYAN}Checking MySQL slave status...${NC}"
  SLAVE_STATUS=$(mysql -e "SHOW SLAVE STATUS\G")
  LAST_SQL_ERROR=$(echo "$SLAVE_STATUS" | grep "Last_SQL_Error:")
  EXEC_MASTER_LOG_POS=$(echo "$SLAVE_STATUS" | grep "Exec_Master_Log_Pos:" | awk '{print $2}')

  echo -e "${YELLOW}$LAST_SQL_ERROR${NC}"
  echo -e "${YELLOW}Exec_Master_Log_Pos: $EXEC_MASTER_LOG_POS${NC}"

  if [[ $(echo "$LAST_SQL_ERROR" | grep -c -E "Error_code: 1032|Error_code: 1062") -gt 0 ]]; then
    echo -e "${RED}Error detected at Exec_Master_Log_Pos: $EXEC_MASTER_LOG_POS. Skipping problematic transaction...${NC}"
    mysql -e "STOP SLAVE; SET GLOBAL SQL_SLAVE_SKIP_COUNTER = 1; START SLAVE;"
    sleep 2 # Give some time for the slave to restart
    NEW_SLAVE_STATUS=$(mysql -e "SHOW SLAVE STATUS\G")
    NEW_EXEC_MASTER_LOG_POS=$(echo "$NEW_SLAVE_STATUS" | grep "Exec_Master_Log_Pos:" | awk '{print $2}')
    echo -e "${GREEN}Skipped one transaction. New Exec_Master_Log_Pos: $NEW_EXEC_MASTER_LOG_POS${NC}"
    if [[ "$NEW_EXEC_MASTER_LOG_POS" == "$EXEC_MASTER_LOG_POS" ]]; then
      echo -e "${RED}Error: Exec_Master_Log_Pos did not change. Exiting...${NC}"
      break
    fi
  else
    echo -e "${GREEN}No relevant error found. Exiting...${NC}"
    break
  fi
  sleep 1
done

echo -e "${CYAN}Script completed successfully.${NC}"
