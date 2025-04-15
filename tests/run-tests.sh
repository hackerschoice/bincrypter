#! /usr/bin/env bash

TEST_PASSWORD="1234567890"

set -e
command -v bincrypter >/dev/null

cat >test.sh <<'EOF'
#!/bin/bash
# Check for leakage:
# set | grep BC | grep -v BC_PASSWORD | grep -v BC_ITER | grep -Fqm1 BC && exit 255
BC_TEST=1
echo "INTERNAL BC_TEST=$BC_TEST"
[ $# -ne 0 ] && exit 244
:
EOF
chmod +x test.sh

### TEST FOR DEBUGGING:
###

echo ">>> Test: File"
cp test.sh t.sh; chmod +x t.sh
bincrypter t.sh
./t.sh
set +e
./t.sh 244
[ $? -ne 244 ] && { echo "Error code is not 244"; exit 255; }
set -e

echo ">>> Test: Source ./t.sh"
unset BC_TEST
source ./t.sh
[ "${BC_TEST:-0}" -ne 1 ] && exit 255
BC_FN=t.sh source ./t.sh
[ "${BC_TEST:-0}" -ne 1 ] && exit 255

echo '>>> Test: BC_FN=t.sh eval "$(cat <t.sh)"'
unset BC_TEST
BC_FN=t.sh eval "$(cat <t.sh)"
[ "${BC_TEST:-0}" -ne 1 ] && exit 255

echo '>>> Test: bash -c "$(cat ./t.sh)"'
bash -c "$(cat ./t.sh)"
# Should also be EXEC string XS:
BC_FN=t.sh bash -c "$(<t.sh)"

echo ">>> Test: Most common use case ${BC_ITER:-100} times"
for ((i=1; i<=${BC_ITER:-100}; i++)); do
    cp test.sh t.sh; chmod +x t.sh
    bincrypter t.sh
    ./t.sh
    unset BC_TEST
    source ./t.sh
    [ "${BC_TEST:-0}" -ne 1 ] && exit 255
done

echo ">>> Test: Pipe"
cat test.sh | bincrypter >t.sh
chmod +x t.sh
unset BC_TEST
./t.sh
source ./t.sh
[ "${BC_TEST:-0}" -ne 1 ] && exit 255

echo ">>> Test: Double (file)"
cp test.sh t.sh; chmod +x t.sh
bincrypter t.sh 
bincrypter t.sh 
./t.sh

echo ">>> Test: Triple (pipe)"
cat test.sh | bincrypter | bincrypter | bincrypter >t.sh
chmod +x t.sh
./t.sh

echo ">>> Test: Set password (by environment variable, PASSWORD=)"
PASSWORD="${TEST_PASSWORD}" BC_PASSWORD="IGNORED" ./bincrypter <test.sh >t.sh
PASSWORD="${TEST_PASSWORD}" ./t.sh
PASSWORD="${TEST_PASSWORD}" BC_PASSWORD="NOT-FAVORED" ./t.sh
echo ">>> Test: Set password (by environment variable, BC_PASSWORD=)"
BC_PASSWORD="${TEST_PASSWORD}" ./bincrypter <test.sh >t.sh
BC_PASSWORD="${TEST_PASSWORD}" ./t.sh
echo "${TEST_PASSWORD}" | ./t.sh 2>/dev/null
# Should fail because password is BAD:
set +e
PASSWORD="${TEST_PASSWORD}-BAD" ./t.sh 2>/dev/null && exit 254
set -e

echo ">>> Test: Set password (by command line)"
cp test.sh t.sh; chmod +x t.sh
bincrypter t.sh "${TEST_PASSWORD}"
PASSWORD="${TEST_PASSWORD}" ./t.sh
echo "${TEST_PASSWORD}" | ./t.sh 2>/dev/null
# Should fail because password is BAD:
set +e
echo "${TEST_PASSWORD}-BAD" | ./t.sh 2>/dev/null && exit 254
set -e

echo ">>> Test: Password by env (nested with BC_PASSWORD) & Double pipe"
PASSWORD="${TEST_PASSWORD}" ./bincrypter <test.sh | bincrypter - "${TEST_PASSWORD}" >t.sh
BC_PASSWORD="${TEST_PASSWORD}" ./t.sh

echo ">>> Test: Nested different Passwords"
BC_PASSWORD="${TEST_PASSWORD}INNER" ./bincrypter <test.sh | bincrypter - "${TEST_PASSWORD}OUTTER" >t.sh
# both by ENV
echo ">>> Test: Nested different Passwords (2x ENV)"
PASSWORD="${TEST_PASSWORD}OUTTER" BC_PASSWORD="${TEST_PASSWORD}INNER" ./t.sh
# 1 ENV 1 STDIN
echo ">>> Test: Nested different Passwords (1x ENV 1x STDIN)"
echo "${TEST_PASSWORD}INNER" | PASSWORD="${TEST_PASSWORD}OUTTER" ./t.sh
# 2x STDIN
echo ">>> Test: Nested different Passwords (2x STDIN)"
echo -e "${TEST_PASSWORD}OUTTER\n${TEST_PASSWORD}INNER" | ./t.sh

echo ">>> Test: BC_LOCK=123"
BC_LOCK=123 ./bincrypter <test.sh >t.sh
./t.sh 
set +e
BC_BCL_TEST_FAIL=1 ./t.sh
[ $? -ne 123 ] && { echo "Error code is not 123"; exit 255; }
set -e

echo ">>> Test: BC_LOCK='id'"
BC_LOCK='id' ./bincrypter <test.sh >t.sh
./t.sh 
set +e
[[ "$(BC_BCL_TEST_FAIL=1 ./t.sh)" != "uid"* ]] && { echo "BC_LOCK did not get executed"; exit 255; }
set -e
echo '===COMPLETED==='
:
