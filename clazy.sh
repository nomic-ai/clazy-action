#!/bin/bash

clazy_options=()

for arg in $EXTRA_ARG; do
    clazy_options+=( "-extra-arg=$arg" )
done
for arg in $EXTRA_ARG_BEFORE; do
    clazy_options+=( "-extra-arg-before=$arg" )
done

if [[ $ONLY_QT == "true" ]]; then
    clazy_options+=( "--only-qt" )
fi
if [[ $QT4_COMPAT == "true" ]]; then
    clazy_options+=( "--qt4-compat" )
fi
if [[ $VISIT_IMPLICIT_CODE == "true" ]]; then
    clazy_options+=( "--visit-implicit-code" )
fi

args=(
    -clang-tidy-binary "$GITHUB_ACTION_PATH/clazy-unbuffer.sh"
    -checks="$CHECKS"
    -warnings-as-errors="$WARNINGS_AS_ERRORS"
    -p="$DATABASE"
    -header-filter="$HEADER_FILTER"
    --
    "$PATH_REGEX"
)

exec 5>&1
output=$(CLAZY_OPTIONS=${clazy_options[*]} run-clang-tidy "${args[@]}" 2>&1 | tee /dev/fd/5)

warnings_file=$(mktemp)
errors_file=$(mktemp)

trap 'rm -f "$warnings_file" "$errors_file"' EXIT

echo 0 > "$warnings_file"
echo 0 > "$errors_file"

declare -A warnings_seen

pattern='^(.*?):([0-9]+):([0-9]+): (.+): (.+) \[(.*)\]$'

echo "$output" | grep -E "$pattern" | while IFS= read -r line; do
    if [[ $line =~ $pattern ]]; then
        relative_path="${BASH_REMATCH[1]}"
        line_number="${BASH_REMATCH[2]}"
        column_number="${BASH_REMATCH[3]}"
        warning_type="${BASH_REMATCH[4]}"
        warning_message="${BASH_REMATCH[5]}"
        warning_code="${BASH_REMATCH[6]}"

        if [[ "$relative_path" == /* ]]; then
            absolute_path=$relative_path
        else
            absolute_path=$(realpath "$DATABASE/$relative_path")
        fi

        warning_key="${absolute_path}:${line_number}:${column_number}:${warning_code}"

        if [[ -n "${warnings_seen[$warning_key]}" ]]; then
            continue
        fi

        warnings_seen["$warning_key"]=1

        if [ "$IGNORE_HEADERS" != "true" ]; then
            if [[ "$warning_type" == "warning" ]]; then
                echo "warning file=$absolute_path,line=$line_number,col=$column_number,$warning_message [$warning_code]"
                current_warnings=$(<"$warnings_file")
                ((current_warnings++))
                echo "$current_warnings" > "$warnings_file"
            fi

            if [[ "$warning_type" == "error" ]]; then
                echo "error file=$absolute_path,line=$line_number,col=$column_number,$warning_message [$warning_code]"
                current_errors=$(<"$errors_file")
                ((current_errors++))
                echo "$current_errors" > "$errors_file"
            fi

        elif [[ "${files[@]}" =~ "$absolute_path" ]]; then

            if [[ "$warning_type" == "warning" ]]; then
                echo "warning file=$absolute_path,line=$line_number,col=$column_number,$warning_message [$warning_code]"
                current_warnings=$(<"$warnings_file")
                ((current_warnings++))
                echo "$current_warnings" > "$warnings_file"
            fi

            if [[ "$warning_type" == "error" ]]; then
                echo "error file=$absolute_path,line=$line_number,col=$column_number,$warning_message [$warning_code]"
                current_errors=$(<"$errors_file")
                ((current_errors++))
                echo "$current_errors" > "$errors_file"
            fi
        fi

        if [[ "${files[@]}" =~ "$absolute_path" ]]; then
            if [[ "$warning_type" == "warning" ]]; then
                echo "::warning file=$absolute_path,line=$line_number,col=$column_number::$warning_message [$warning_code]"
            fi

            if [[ "$warning_type" == "error" ]]; then
                echo "::error file=$absolute_path,line=$line_number,col=$column_number::$warning_message [$warning_code]"
            fi
        fi
    fi
done

warnings_count=$(<"$warnings_file")
errors_count=$(<"$errors_file")

echo "::set-output name=errors-count::$errors_count"
echo "::set-output name=warnings-count::$warnings_count"

if [ "$IGNORE_HEADERS" == "true" ] && [ -n "$DATABASE" ]; then
    mv $DATABASE/compile_commands_backup.json $DATABASE/compile_commands.json
fi

rm -f "$warnings_file" "$errors_file"
