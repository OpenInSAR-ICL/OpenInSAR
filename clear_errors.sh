#!/bin/bash
for file in *.worker; do 
    if grep -q 'MException' "$file"; then 
        echo "Clearing contents of $file"
        > "$file"
    fi
done

rm error*.txt
