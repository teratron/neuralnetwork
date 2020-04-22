package nn

import (
	"math"
	"math/rand"
	"time"
)

// Collection of neural network matrix parameters
// Коллекция параметров матрицы нейросети
type Matrix struct {
	Size	int			// Количество слоёв в нейросети (Input + Hidden + Output)
	Index	int			// Индекс выходного (последнего) слоя нейросети
	Mode	uint8		// Идентификатор функции активации
	Bias	float32		// Нейрон смещения: от 0 до 1
	Ratio 	float32		// Коэффициент обучения, от 0 до 1
	Limit	float32		// Минимальный уровень квадратичной суммы ошибки при обучения
	Data	[]float32	// Обучающий набор с которым будет сравниваться выходной слой
	Layer	[]Layer		// Коллекция слоя
	Synapse	[]Synapse	// Коллекция весов связей
}

// Collection of neural layer parameters
// Коллекция параметров нейронного слоя
type Layer struct {
	Size	int			// Количество нейронов в слое
	Neuron	[]float32	// Значения нейрона
	Error	[]float32	// Значение ошибки
}

// Collection of weight parameters
// Коллекция параметров весов
type Synapse struct {
	Size	[]int		// Количество связей весов {X, Y}, X - входной (предыдущий) слой, Y - выходной (следующий) слой
	Weight	[][]float32	// Значения весов
}

func init() {
}

//
func GetOutput(bias float32, input []float32, matrix *Matrix) []float32 {
	matrix.CalcNeuron()
	return matrix.Layer[matrix.Index].Neuron
}

// Matrix initialization function
// Функция инициализации матрицы
func (m *Matrix) Init(mode uint8, bias, ratio float32, input, data []float32, hidden []int) {
	var i, j int
	layer := []int{len(input)}
	for _, v := range hidden {
		layer = append(layer, v)
	}
	layer     = append(layer, len(data))
	m.Size    = len(layer)
	m.Index   = m.Size - 1
	m.Layer   = make([]Layer,   m.Size)
	m.Synapse = make([]Synapse,  m.Index)
	m.Data    = make([]float32, m.Index)
	m.Ratio   = ratio
	m.Mode    = mode
	for i, j = range layer {
		m.Layer[i].Size = j
	}
	switch {
	case bias < 0: m.Bias = 0
	case bias > 1: m.Bias = 1
	default: 	   m.Bias = bias
	}
	for i = 0; i < m.Size; i++ {
		// Создаем срезы для структуры нейронных слоёв и весов
		m.Layer[i].Neuron = make([]float32, m.Layer[i].Size)
		if i > 0 {
			m.Layer[i].Error = make([]float32, m.Layer[i].Size)
		}
		if i < m.Index {
			m.Layer[i].Neuron = append(m.Layer[i].Neuron, m.Bias)
			m.Synapse[i].Size    = []int{m.Layer[i].Size + 1, m.Layer[i + 1].Size}
			m.Synapse[i].Weight  = make([][]float32, m.Synapse[i].Size[0])
			for j = 0; j < m.Synapse[i].Size[0]; j++ {
				m.Synapse[i].Weight[j] = make([]float32, m.Synapse[i].Size[1])
			}
		}
	}
	copy(m.Layer[0].Neuron, input)
	copy(m.Data, data)
}

// The function fills all weights with random numbers from -0.5 to 0.5
// Функция заполняет все веса случайными числами от -0.5 до 0.5
func (m *Matrix) FillWeight() {
	rand.Seed(time.Now().UTC().UnixNano())
	for i := 0; i < m.Index; i++ {
		n := m.Synapse[i].Size[0] - 1
		for j := 0; j < m.Synapse[i].Size[0]; j++ {
			for k := 0; k < m.Synapse[i].Size[1]; k++ {
				if j == n && m.Bias == 0 {
					m.Synapse[i].Weight[j][k] = 0
				} else {
					m.Synapse[i].Weight[j][k] = rand.Float32() - .5
				}
			}
		}
	}
}

// Function for calculating the values of neurons in a layer
// Функция вычисления значений нейронов в слое
func (m *Matrix) CalcNeuron() {
	for i := 1; i < m.Size; i++ {
		n := i - 1
		for j := 0; j < m.Layer[i].Size; j++ {
			var sum float32 = 0
			for k, v := range m.Layer[n].Neuron {
				sum += v * m.Synapse[n].Weight[k][j]
			}
			m.Layer[i].Neuron[j] = GetActivation(sum, m.Mode)
		}
	}
}

// Function for calculating the error of the output neuron
// Функция вычисления ошибки выходного нейрона
func (m *Matrix) CalcOutputError() (fault float32) {
	fault = 0
	for i, v := range m.Layer[m.Index].Neuron {
		m.Layer[m.Index].Error[i] = (m.Data[i] - v) * GetDerivative(v, m.Mode)
		fault += float32(math.Pow(float64(m.Layer[m.Index].Error[i]), 2))
	}
	return fault
}

// Function for calculating the error of neurons in hidden layers
// Функция вычисления ошибки нейронов в скрытых слоях
func (m *Matrix) CalcError() {
	for i := m.Size - 2; i > 0; i-- {
		for j := 0; j < m.Layer[i].Size; j++ {
			var sum float32 = 0
			for k, v := range m.Layer[i + 1].Error {
				sum += v * m.Synapse[i].Weight[j][k]
			}
			m.Layer[i].Error[j] = sum * GetDerivative(m.Layer[i].Neuron[j], m.Mode)
		}
	}
}

// Weights update function
// Функция обновления весов
func (m *Matrix) UpdWeight() {
	for i := 1; i < m.Size; i++ {
		n := i - 1
		for j, v := range m.Layer[i].Error {
			for k, p := range m.Layer[n].Neuron {
				m.Synapse[n].Weight[k][j] += m.Ratio * v * p * GetDerivative(m.Layer[i].Neuron[j], m.Mode)
			}
		}
	}
}