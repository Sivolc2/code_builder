from calculator import Calculator

def main():
    """
    Demonstrate the use of the Calculator class.
    """
    calc = Calculator()
    
    # Demonstrate addition
    a, b = 10, 5
    result = calc.add(a, b)
    print(f"{a} + {b} = {result}")
    
    # Demonstrate subtraction
    result = calc.subtract(a, b)
    print(f"{a} - {b} = {result}")
    
    # Demonstrate multiplication
    result = calc.multiply(a, b)
    print(f"{a} * {b} = {result}")
    
    # Demonstrate division
    result = calc.divide(a, b)
    print(f"{a} / {b} = {result}")
    
    # Demonstrate division by zero error handling
    try:
        result = calc.divide(a, 0)
    except ZeroDivisionError as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
