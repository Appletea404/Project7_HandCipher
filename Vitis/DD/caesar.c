#include "caesar.h"

// 글자를 shift만큼 뒤로 밀어 암호화 (예: A + 3 = D)
char caesar_encode(char c, int shift) {
    if (c >= 'A' && c <= 'Z') {
        return 'A' + (c - 'A' + shift) % 26;
    }
    return c;
}

// 글자를 shift만큼 앞으로 당겨 복호화 (예: D - 3 = A)
char caesar_decode(char c, int shift) {
    if (c >= 'A' && c <= 'Z') {
        return 'A' + (c - 'A' + 26 - shift) % 26;
    }
    return c;
}