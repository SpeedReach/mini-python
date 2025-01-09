.data
    none: .string "None\n"
    true: .string "True\n"
    false: .string "False\n"
    integer: .string "%d\n"
    panic_str: .string "error\n"


.text

.macro malloc size
    subq    $8, %rsp
    movq    \size, (%rsp)
    call my_malloc
    addq    $8, %rsp
.endm


.globl main
main:
    # Alloc two int first
    malloc  $16
    movq    $2, (%rax)
    movq    $3, 8(%rax)
    pushq   %rax
    malloc  $16
    movq    $2, (%rax)
    movq    $9, 8(%rax)
    pushq   %rax


    popq    %rsi
    popq    %rdx
    call    _builtin_add

    pushq   %rax
    call    print

    movq    $60, %rax                 # System call number for `exit`
    xorq    %rdi, %rdi                # Status 0 (successful exit)
    syscall                           # Make the system call


_builtin_add:
    pushq   %rbp
    movq    %rsp, %rbp

    movq    (%rsi), %r8           # Check if same type
    movq    (%rdx), %r9
    cmpq    %r8, %r9
    jne runtime_panic           # Should be same type
    cmpq    $0, %r8
    je  runtime_panic           # Add None is not supported
    cmpq    $1, %r8
    je  runtime_panic           # Add Bool is not supported
    cmpq    $2, %r8
    je  add_int
    cmpq    $3, %r8
    je  add_str
    cmpq    $4, %r8
    je  add_list

add_int:
    movq    8(%rsi), %r8
    movq    8(%rdx), %r9
    addq    %r8, %r9
    pushq   %r9
    
    # alloc memory for add result
    malloc  $16
    movq    $2, (%rax)
    popq    %r9
    movq    %r9, 8(%rax)

    movq    %rbp, %rsp
    popq    %rbp
    ret


    

add_str:
add_list:


runtime_panic:
    andq $-16, %rsp
    leaq panic_str(%rip), %rdi   # Load address of format string into %rdi
    xorq %rax, %rax         # Set %rax to 0 as required for variadic functions

    call printf             # Call the `printf` function
    movq    $60, %rax                     # System call number for `exit`
    xorq    %rdi, %rdi                    # Status 0 (successful exit)
    syscall                           # Make the system call


my_malloc:
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp
    movq    16(%rbp), %rdi
    call    malloc
    movq    %rbp, %rsp
    popq    %rbp
    ret



print:
    pushq   %rbp
    movq    %rsp, %rbp

    movq    16(%rbp), %rbx  # get arg0 , which is a pointer to the value

    movq    (%rbx), %rcx    # get the type, which is the first 64 bits
    
    addq    $8, %rbx        # move the pointer to the value to the next 64 bits 
    subq    $8, %rsp        # and store it as arg0 for call_print_xxx 
    movq    %rbx, (%rsp)
    
    cmpq    $0, %rcx
    je  call_print_none
    cmpq    $1, %rcx
    je  call_print_bool
    cmpq    $2, %rcx
    je  call_print_int
    cmpq    $3, %rcx
    je  call_print_str
print_end:
    addq    $8,  %rsp
    movq    %rbp, %rsp
    popq    %rbp
    ret

call_print_none:
    call    print_none
    jmp print_end
call_print_bool:
    call    print_bool
    jmp print_end
call_print_int:
    call    print_int
    jmp print_end
call_print_str:
    call    print_string
    jmp print_end

print_int:
    pushq   %rbp
    movq    %rsp, %rbp 
    andq    $-16, %rsp              # 16bit alignment

    movq    16(%rbp), %rsi          # Get arg0 , which is the pointer to the int.
    movq    (%rsi), %rsi            # Move the int to %rsi, which is the second argument in printf 
    leaq    integer(%rip), %rdi     # Load address of format string into %rdi
    xorq    %rax, %rax              # Set %rax to 0 as required for variadic functions

    call    printf                  # Call the `printf` function
    movq    %rbp, %rsp
    popq    %rbp
    ret 
    
print_none:
    pushq %rbp
    movq    %rsp, %rbp 
    andq $-16, %rsp
    leaq none(%rip), %rdi   # Load address of format string into %rdi
    xorq %rax, %rax         # Set %rax to 0 as required for variadic functions

    call printf             # Call the `printf` function
    movq %rbp, %rsp
    popq %rbp
    ret 

#Arg 1 = ptr to bool memory 
print_bool:
    pushq   %rbp
    movq    %rsp, %rbp 
    andq    $-16, %rsp
    movq    16(%rbp), %rax
    movq    (%rax), %rax
    cmpq    $0, %rax
    je  print_false
    jmp print_true

print_true:
    leaq    true(%rip), %rdi    # Load address of format string into %rdi
    xorq    %rax, %rax          # Set %rax to 0 as required for variadic functions
    call    printf              # Call the `printf` function

    movq    %rbp, %rsp
    popq    %rbp
    ret 

print_false:
    leaq    false(%rip), %rdi   # Load address of format string into %rdi
    xorq    %rax, %rax          # Set %rax to 0 as required for variadic functions
    call    printf              # Call the `printf` function

    movq    %rbp, %rsp
    popq    %rbp
    ret 

# Basically, we do a 
# for(int i=0;i<n;i++) 
#   putchar(s[i]) 
print_string:
    pushq   %rbp
    movq    %rsp, %rbp

    movq    16(%rbp), %rbx          # Get arg0 , which is the pointer to the length
    subq    $24, %rsp               # which is -8(%rbp)
    movq    (%rbx), %rcx            # Save the length on -8(%rbp)
    movq    %rcx, 16(%rsp)            

    movq    %rbx, %rcx              # Store the pointer to the string on -16(%rbp)
    addq    $8, %rcx                # Add 1 byte, because the string starts at second index.
    movq    %rcx, 8(%rsp)

print_string_for_init:
    movq    $0, (%rsp)              # Initialize i=0, and store it on -24(%rbp)
print_string_for_cond:
    movq    -8(%rbp), %rbx          # Set rbx to length
    movq    -24(%rbp), %rcx         # Set rcx to i
    cmpq    %rbx, %rcx 
    jge print_string_for_end
print_string_for_inner:
    movq    -16(%rbp), %rbx         # Set rbx to the pointer to the start of the string
    movq    -24(%rbp), %rcx         # Set rcx to i
    imulq   $8, %rcx                # Since every char is 8 bytes in mini-python, we have to * 8
    addq    %rbx, %rcx              # Get pointer to str[i]
    movq    (%rcx), %rcx            # Move the char at str[i] to rcx 
                                    #
    subq    $8, %rsp                # Prepare my_putchar arg0 
    movq    %rcx, (%rsp)            # 
    call    my_putchar
    addq    $8, %rsp

    movq    -24(%rbp), %rbx         # Perform i++
    addq    $1, %rbx                #
    movq    %rbx, -24(%rbp)         #

    jmp print_string_for_cond
print_string_for_end:
    subq    $8, %rsp
    movq    $10,(%rsp)
    call    my_putchar
    addq    $8, %rsp

    movq    %rbp, %rsp
    popq    %rbp
    ret 
    
    subq    $8, %rsp
    movq    %rsi, (%rsp)
    call    my_putchar
    subq    $8, %rsp
    movq    $10,(%rsp)
    call    my_putchar

    addq    $16, %rsp

    movq    %rbp, %rsp
    popq    %rbp
    ret 

my_putchar:
    pushq   %rbp
    movq    %rsp, %rbp
    movq    16(%rbp), %rdi
    andq    $-16, %rsp
    call    putchar
    movq    %rbp, %rsp
    popq    %rbp
    ret