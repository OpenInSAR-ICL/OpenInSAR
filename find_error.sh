

for file in error*; do
#    echo "File: $file"
    awk -F'<message>|</message>' '/<message>/{print $2}' "$file" | grep -oP 'MAT-file \K\S+\.mat'
#    echo "--------------------------"
done

