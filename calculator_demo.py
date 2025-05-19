from calculator import Calculator

def main():
    """
    Demonstrate the use of the Calculator class.
    """
    # Create an instance of the Calculator class
    calc = Calculator()
    
    # Demonstrate addition
    print(f"10 + 5 = {calc.add(10, 5)}")
    
    # Demonstrate subtraction
    print(f"10 - 5 = {calc.subtract(10, 5)}")
    
    # Demonstrate multiplication
    print(f"10 * 5 = {calc.multiply(10, 5)}")
    
    # Demonstrate division
    print(f"10 / 5 = {calc.divide(10, 5)}")
    
    # Demonstrate division by zero handling
    try:
        result = calc.divide(10, 0)
    except ZeroDivisionError as e:
        print(f"Caught an exception: {e}")

if __name__ == "__main__":
    main()
