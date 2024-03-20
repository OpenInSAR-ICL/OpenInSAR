#!/bin/bash
for file in *.worker; do 
    if grep -q 'MException' "$file"; then 
        echo "Clearing contents of $file"
        echo "RESET" > "$file"
    fi
done

rm error*.txt
