package main

/*
#include <stdio.h>

void hello() {
    printf("Hello from Go CGO verified binary!\n");
}
*/
import "C"

func main() {
	C.hello()
}
