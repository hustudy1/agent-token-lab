#!/bin/bash
# macOS: Finder에서 더블클릭하면 터미널이 열리고 설정 메뉴가 실행된다.
cd "$(dirname "$0")" || exit 1
bash ./setup.sh
printf '\n엔터를 누르면 창을 닫습니다.'
read -r _
