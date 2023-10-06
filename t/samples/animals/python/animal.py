class Animal:
    def name(self) -> str:
        pass

class Mammal(Animal):
    def close(self):
        pass

class Cat(Mammal):
    def __init__ (self, name):
        self.__name = name
    def name(self) -> str:
        return self.__name

class Dog(Mammal):
    def __init__ (self, name):
        self.__name = name
    def name(self) -> str:
        return self.__name

def main(): 
    dog: Animal = Dog("Odie");
    cat: Mammal = Cat("Garfield");
    print(dog.name())
    print(cat.name())

if __name__ == '__main__':
    main()

