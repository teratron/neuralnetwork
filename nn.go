package main

import (
	"./lib"
	"fmt"
	"io/ioutil"
	"log"
	"math"
	"math/rand"
	"strconv"
)

// Коллекция параметров матрицы
type NNMatrix struct {
	Size	int				// Количество слоёв в нейросети (Input + Hidden + Output)
	Bias	float32			// Нейрон смещения
	Ratio 	float32			// Коэффициент обучения, от 0 до 1
	Data	[]float32		// Обучающий набор с которым будет сравниваться выходной слой
	Layer	[]NNLayer		// Коллекция слоя
	Weight	[]NNWeight		// Коллекция весов
}

// Коллекция параметров нейронного слоя
type NNLayer struct {
	Size	int				// Количество нейронов в слое
	Neuron	[]float32		// Значения нейрона
	Error	[]float32		// Значение ошибки
}

// Коллекция параметров весов
type NNWeight struct {
	Size	[]int			// Количество связей весов {X, Y}, X - входной (предыдущий) слой, Y - выходной (следующий) слой
	Weight	[][]float32		// Значения весов
}

func main() {
	var (
		collision	float32
		bias		float32	= 0
		ratio		float32	= .5
		input	= []float32{1.2, 6.3}	// Входные параметры
		data	= []float32{6.3, 3.2}	// Обучающий набор с которым будет сравниваться выходной слой
		hidden	= []int{5, 4}			// Массив количеств нейронов в каждом скрытом слое
	)

	// Инициализация нейронных слоёв и весов (матрицы)
	matrix := NNMatrix{}
	matrix.InitNN(bias, ratio, input, data, hidden)

	// Обучение нейронной сети за какое-то количество эпох
	for i := 0; i < 1000; i++ {
		matrix.CalcNeuron()                  // Вычисляем значения нейронов в слое
		collision = matrix.CalcOutputError() // Вычисляем ошибки между обучающим набором и полученными выходными нейронами
		matrix.CalcError()                   // Вычисляем ошибки нейронов в скрытых слоях
		matrix.UpdWeight()                   // Обновление весов
	}

	fmt.Println(lib.Get("cs"))

	err := matrix.WriteWeight()
	if err != nil {
		log.Fatal(err)
	}

	// Вывод значений нейросети
	matrix.PrintNN(collision)
}

//
func Get() {

}

// Функция инициализации матрицы
func (matrix *NNMatrix) InitNN(bias float32, ratio float32, input []float32, data []float32, hidden []int) {
	var i, j, index int
	layer := []int{len(input)}
	for _, v := range hidden {
		layer = append(layer, v)
	}
	layer = append(layer, len(data))
	matrix.Size		= len(layer)
	index			= matrix.Size - 1
	matrix.Layer	= make([]NNLayer,  matrix.Size)
	matrix.Weight	= make([]NNWeight, index)
	matrix.Data		= make([]float32,  index)
	matrix.Ratio	= ratio
	for i, j = range layer {
		matrix.Layer[i].Size = j
	}
	switch {
	case bias < 0:	matrix.Bias = 0
	case bias > 1:	matrix.Bias = 1
	default: 		matrix.Bias = bias
	}
	for i = 0; i < matrix.Size; i++ {
		// Создаем срезы для структуры нейронных слоёв и весов
		matrix.Layer[i].Neuron = make([]float32, matrix.Layer[i].Size)
		if i > 0 {
			matrix.Layer[i].Error = make([]float32, matrix.Layer[i].Size)
		}
		if i < index {
			matrix.Layer[i].Neuron  = append(matrix.Layer[i].Neuron, matrix.Bias)
			matrix.Weight[i].Size   = []int{matrix.Layer[i].Size + 1, matrix.Layer[i + 1].Size}
			matrix.Weight[i].Weight = make([][]float32, matrix.Weight[i].Size[0])
			for j = 0; j < matrix.Weight[i].Size[0]; j++ {
				matrix.Weight[i].Weight[j] = make([]float32, matrix.Weight[i].Size[1])
			}
			// Заполняем все веса случайными числами от -0.5 до 0.5
			matrix.Weight[i].FillRandWeight(matrix.Bias)
		}
	}
	copy(matrix.Layer[0].Neuron, input)
	copy(matrix.Data, data)
}

// Функция заполняет все веса случайными числами от -0.5 до 0.5
func (weight *NNWeight) FillRandWeight(bias float32) {
	n := weight.Size[0] - 1
	for i := 0; i < weight.Size[0]; i++ {
		for j := 0; j < weight.Size[1]; j++ {
			weight.Weight[i][j] = rand.Float32() - .5
			if i == n {
				weight.Weight[i][j] *= bias
			}
		}
	}
}

// Функция вычисления значения нейронов в слое
func (matrix *NNMatrix) CalcNeuron() {
	for i := 1; i < matrix.Size; i++ {
		n := i - 1
		for j := 0; j < matrix.Layer[i].Size; j++ {
			var sum float32 = 0
			for k, v := range matrix.Layer[n].Neuron {
				sum += v * matrix.Weight[n].Weight[k][j]
			}
			matrix.Layer[i].Neuron[j] = GetActivation(sum, 0)
		}
	}
}

// Функция вычисления ошибки выходного нейрона
func (matrix *NNMatrix) CalcOutputError() (collision float32) {
	collision = 0
	j := matrix.Size - 1
	for i, v := range matrix.Layer[j].Neuron {
		matrix.Layer[j].Error[i] = (matrix.Data[i] - v) * GetDerivative(v, 0)
		collision += (float32)(math.Pow((float64)(matrix.Layer[j].Error[i]), 2))
	}
	return collision
}

// Функция вычисления ошибки нейронов в скрытых слоях
func (matrix *NNMatrix) CalcError() {
	for i := matrix.Size - 2; i > 0; i-- {
		for j := 0; j < matrix.Layer[i].Size; j++ {
			var sum float32 = 0
			for k, v := range matrix.Layer[i + 1].Error {
				sum += v * matrix.Weight[i].Weight[j][k]
			}
			matrix.Layer[i].Error[j] = sum * GetDerivative(matrix.Layer[i].Neuron[j], 0)
		}
	}
}

// Функция обновления весов
func (matrix *NNMatrix) UpdWeight() {
	for i := 1; i < matrix.Size; i++ {
		n := i - 1
		for j, v := range matrix.Layer[i].Error {
			for k, p := range matrix.Layer[n].Neuron {
				if k == matrix.Layer[n].Size && matrix.Bias == 0 {
					continue
				}
				matrix.Weight[n].Weight[k][j] += matrix.Ratio * v * p * GetDerivative(matrix.Layer[i].Neuron[j], 0)
			}
		}
	}
}

// Функция активации нейрона
func GetActivation(value float32, mode uint8) float32 {
	switch mode {
	default: fallthrough
	case 0: return (float32)(1 / (1 + math.Pow(math.E, (float64)(-value)))) // Sigmoid
	case 1: // Leaky ReLu
		switch {
		case value < 0: return 0.01 * value
		case value > 1: return 1 + 0.01 * (value - 1)
		default:	  return value
		}
	case 2: return (float32)(2 / (1 + math.Pow(math.E, (float64)(-2 * value))) - 1) // Tanh - гиперболический тангенс
	}
}

// Функция производной активации
func GetDerivative(value float32, mode uint8) float32 {
	switch mode {
	default: fallthrough
	case 0: return value * (1 - value)
	case 1: return 1
	}
}

// Функция вывода результатов нейросети
func (matrix *NNMatrix) PrintNN(collision float32) {
	t := "Layer"
	n := matrix.Size - 1
	for i := 0; i < matrix.Size; i++ {
		if i == len(matrix.Layer) - 1 {
			t = " Output layer"
		}
		fmt.Println(i, t, "size: ", matrix.Layer[i].Size)
		fmt.Println("Neurons:\t", matrix.Layer[i].Neuron)
		fmt.Println("Errors:\t\t", matrix.Layer[i].Error)
	}
	fmt.Println("Weights:")
	for i := 0; i < n; i++ {
		fmt.Println(matrix.Weight[i].Weight)
	}
	fmt.Println("Total Error:\t", collision)
}

//
func (matrix *NNMatrix) WriteWeight() error {
	message := []byte(strconv.FormatFloat((float64)(matrix.Weight[0].Weight[0][0]), 'f', -1, 32))
	err := ioutil.WriteFile("weight.data", message, 0644)
	if err != nil {
		log.Fatal(err)
	}
	return err
}