class Calculator:
    """
    A simple calculator class that provides basic arithmetic operations.
    """
    
    def __init__(self):
        """
        Initialize the Calculator instance.
        """
        pass
    
    def add(self, a, b):
        """
        Add two numbers and return the result.
        
        Args:
            a (int/float): First number
            b (int/float): Second number
            
        Returns:
            int/float: The sum of a and b
        """
        return a + b
    
    def subtract(self, a, b):
        """
        Subtract b from a and return the result.
        
        Args:
            a (int/float): First number
            b (int/float): Second number
            
        Returns:
            int/float: The difference of a and b
        """
        return a - b
    
    def multiply(self, a, b):
        """
        Multiply two numbers and return the result.
        
        Args:
            a (int/float): First number
            b (int/float): Second number
            
        Returns:
            int/float: The product of a and b
        """
        return a * b
    
    def divide(self, a, b):
        """
        Divide a by b and return the result.
        
        Args:
            a (int/float): Numerator
            b (int/float): Denominator
            
        Returns:
            float: The quotient of a and b
            
        Raises:
            ZeroDivisionError: If b is zero
        """
        if b == 0:
            raise ZeroDivisionError("Cannot divide by zero")
        return a / b
