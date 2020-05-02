package nn

import (
	"math"
	"math/rand"
	"time"
)

const (
	DEFRATE	float32	= .3
	MINLOSS	float32	= .001		// Минимальная величина средней квадратичной суммы ошибки при достижении которой обучение прекращается принудительно
	MAXITER	int 	= 1000000	// Максимальная количество иттреаций по достижению которой обучение прекращается принудительно
)

// Collection of neural network matrix parameters
type Matrix struct {
	Init	bool		// Флаг выполнения инициализации матрицы
	Size	int			// Количество слоёв в нейросети (Input + Hidden + Output)
	Index	int			// Индекс выходного (последнего) слоя нейросети
	Mode	uint8		// Идентификатор функции активации
	Bias	float32		// Нейрон смещения: от 0 до 1
	Rate 	float32		// Коэффициент обучения, от 0 до 1
	Limit	float32		// Минимальный (достаточный) уровень средней квадратичной суммы ошибки при обучения
	Hidden	[]int		// Массив количеств нейронов в каждом скрытом слое
	Layer	[]Layer		// Коллекция слоя
	Synapse	[]Synapse	// Коллекция весов связей
}

// Collection of neural layer parameters
type Layer struct {
	Size	int			// Количество нейронов в слое
	Neuron	[]float32	// Значения нейрона
	Error	[]float32	// Значение ошибки
}

// Collection of weight parameters
type Synapse struct {
	Size	[]int		// Количество связей весов {X, Y}, X - входной (предыдущий) слой, Y - выходной (следующий) слой
	Weight	[][]float32	// Значения весов
}

// Matrix initialization function
func (m *Matrix) InitMatrix(mode uint8, bias, rate, limit float32, input, data []float32, hidden []int) {
	m.Mode   = mode
	m.Hidden = hidden
	m.Bias   = checkBias(bias)
	m.Rate   = checkRate(rate)
	m.Limit  = checkLimit(limit)
	m.Init   = m.Initializing(input, data)
}

// Matrix initialization function
func (m *Matrix) Initializing(input, data []float32) bool {
	var i, j int
	layer := []int{len(input)}

	if m.Hidden != nil {
		for i, j = range m.Hidden {
			if j > 0 {
				layer = append(layer, j)
			}
		}
	}
	layer     = append(layer, len(data))
	m.Size    = len(layer)
	m.Index   = m.Size - 1
	m.Layer   = make([]Layer,   m.Size)
	m.Synapse = make([]Synapse, m.Index)
	for i, j = range layer {
		m.Layer[i].Size = j
	}
	for i = 0; i < m.Size; i++ {
		m.Layer[i].Neuron = make([]float32, m.Layer[i].Size)
		if i > 0 {
			m.Layer[i].Error = make([]float32, m.Layer[i].Size)
		}
		if i < m.Index {
			m.Layer[i].Neuron   = append(m.Layer[i].Neuron, m.Bias)
			m.Synapse[i].Size   = []int{m.Layer[i].Size + 1, m.Layer[i + 1].Size}
			m.Synapse[i].Weight = make([][]float32, m.Synapse[i].Size[0])
			for j = 0; j < m.Synapse[i].Size[0]; j++ {
				m.Synapse[i].Weight[j] = make([]float32, m.Synapse[i].Size[1])
			}
		}
	}
	copy(m.Layer[0].Neuron, input)
	m.FillWeight()
	return true
}

// Training
func (m *Matrix) Training(input, data []float32) (count int, loss float32) {
	if !m.Init {
		m.Init = m.Initializing(input, data)
	}
	count = 1
	for count <= MAXITER {
		if loss = m.GetOutput(data); loss <= m.Limit || loss <= MINLOSS {
			break
		}
		m.CalcError()
		m.UpdWeight()
		count++
	}
	return count, loss
}

//
func (m *Matrix) GetOutput(data []float32) float32 {
	m.CalcNeuron()
	return m.CalcOutputError(data)
}

func checkBias(bias float32) float32 {
	switch {
	case bias < 0: return 0
	case bias > 1: return 1
	default: 	   return bias
	}
}

func checkLimit(limit float32) float32 {
	switch {
	case limit < 0: return MINLOSS
	default:		return limit
	}
}

func checkRate(rate float32) float32 {
	switch {
	case rate < 0 || rate > 1: return DEFRATE
	default:				   return rate
	}
}

// The function fills all weights with random numbers from -0.5 to 0.5
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
func (m *Matrix) CalcOutputError(data []float32) (loss float32) {
	loss = 0
	for i, v := range m.Layer[m.Index].Neuron {
		m.Layer[m.Index].Error[i] = (data[i] - v) * GetDerivative(v, m.Mode)
		loss += float32(math.Pow(float64(m.Layer[m.Index].Error[i]), 2))
	}
	return loss / float32(m.Layer[m.Index].Size)
}

// Function for calculating the error of neurons in hidden layers
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
func (m *Matrix) UpdWeight() {
	for i := 1; i < m.Size; i++ {
		n := i - 1
		for j, v := range m.Layer[i].Error {
			for k, p := range m.Layer[n].Neuron {
				m.Synapse[n].Weight[k][j] += m.Rate * v * p * GetDerivative(m.Layer[i].Neuron[j], m.Mode)
			}
		}
	}
}
