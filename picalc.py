#!/usr/bin/python3

def generate_pi_digits(limit):
    # Инициализация переменных
    q, r, t, k, n, l = 1, 0, 1, 1, 3, 3
    
    pi_digits = ""  # Здесь копятся числа после запятой
    count = 0
    
    while count < limit:
        if 4 * q + r - t < n * t:
            # Найдена очередная цифра
            if count == 0:
                pi_digits += str(n) + "."  # Выделили целую часть (3)
            else:
                pi_digits += str(n)        # Копим цифры после запятой
            
            count += 1
            
            # Перевычисление переменных при генерации цифры
            q, r, n = 10 * q, 10 * (r - n * t), (10 * (3 * q + r)) // t - 10 * n
        else:
            # Перевычисление переменных для уточнения точности
            q, r, t, k, n, l = q * k, (2 * q + r) * l, t * l, k + 1, (q * (7 * k + 2) + r * l) // (t * l), l + 2

    return pi_digits

# Выводим 3 и первые 20 знаков после запятой
print(generate_pi_digits(600))

