/*
* phase_triangulation.cpp 
* Takes a coherence matrix and finds the phase vector which best fits the data, maximising the real part of the matrix product of the coherence matrix and the phase vector.
* Usage : from MATLAB
*         >> principal_phase_vector = arrayProduct([nDays,nIters],coherenceMatrix,phaseVector)
*
* This is a C++ MEX-file for MATLAB.
*
*/
#include <iostream>
#include "mex.hpp"
#include "mexAdapter.hpp"
#include <MatlabDataArray.hpp>
#include <cmath>


class MexFunction : public matlab::mex::Function {
public:
    
    // Pointer to MATLAB engine to call fprintf
    std::shared_ptr<matlab::engine::MATLABEngine> matlabPtr = getEngine();

    // Factory to create MATLAB data arrays
    matlab::data::ArrayFactory factory;
   
    void operator()(matlab::mex::ArgumentList outputs, matlab::mex::ArgumentList inputs) {
        checkArguments(outputs, inputs);
        
        // Initialize input parameters
        size_t nD = inputs[0][0];
        size_t nI = inputs[0][1];
        // Initialize input idxtMTX data
        auto coherence_matrix = getDataPtr<std::complex<double>>(inputs[1]);
        auto phase_vector = getDataPtr<std::complex<double>>(inputs[2]);
        outputs[0] = factory.createArray<std::complex<double>>({nD,1});
        // Get the output pointer
        auto output = getOutDataPtr<std::complex<double>>(outputs[0]);

        // Get the size of the coherence matrix
        size_t m = inputs[1].getDimensions()[0];
        size_t n = inputs[1].getDimensions()[1];
        // Get the size of the phase vector
        size_t p = inputs[2].getDimensions()[0];
        size_t q = inputs[2].getDimensions()[1];
        
        // Copy the phase vector to the output
        std::copy(phase_vector, phase_vector + p, output);

        // Now multiply the coherence matrix by the phase vector N times
        for (int nIters = 0; nIters < nI; nIters++) {
            // For each element of the phase vector
            for (int vIndex = 0; vIndex < p; vIndex++) {
                // Initialize the real and imaginary parts of the matrix product
                double realPart = 0;
                double imagPart = 0;
                // For each element of the coherence matrix at row vIndex
                for (int mIndex = 0; mIndex < m; mIndex++) {
                    // Multiply the real and imaginary parts of the coherence matrix by the real and imaginary parts of the phase vector in the output
                    realPart += coherence_matrix[vIndex * m + mIndex].real() * output[mIndex].real() - coherence_matrix[vIndex * m + mIndex].imag() * output[mIndex].imag();
                    imagPart += coherence_matrix[vIndex * m + mIndex].real() * output[mIndex].imag() + coherence_matrix[vIndex * m + mIndex].imag() * output[mIndex].real();
                }
                // Set the real and imaginary parts of the output to the real and imaginary parts of the matrix product
                output[vIndex].real(realPart);
                output[vIndex].imag(imagPart);
            }
        }

        // Copy the phase vector to the output
        std::copy(phase_vector, phase_vector + p, getOutDataPtr<std::complex<double>>(outputs[0]));
    }

    void checkArguments(matlab::mex::ArgumentList outputs, matlab::mex::ArgumentList inputs) {
        std::shared_ptr<matlab::engine::MATLABEngine> matlabPtr = getEngine();
        matlab::data::ArrayFactory factory;

        if (inputs.size() != 3) {
            matlabPtr->feval(u"error", 
                0, std::vector<matlab::data::Array>({ factory.createScalar("3 inputs required") }));
        }

        if (inputs[0].getNumberOfElements() != 2) {
            matlabPtr->feval(u"error", 
                0, std::vector<matlab::data::Array>({ factory.createScalar("Need 2 input parameters") }));
        }
        
        if (inputs[0].getType() != matlab::data::ArrayType::INT32) {
            matlabPtr->feval(u"error", 
                0, std::vector<matlab::data::Array>({ factory.createScalar("Input parameter must be integer") }));
        }

        if (inputs[1].getType() == matlab::data::ArrayType::DOUBLE ||
            inputs[1].getType() != matlab::data::ArrayType::COMPLEX_DOUBLE) {
            matlabPtr->feval(u"error", 
                0, std::vector<matlab::data::Array>({ factory.createScalar("Input idxtMTX must be type complex double") }));
        }

        if (inputs[1].getDimensions().size() != 2) {
            matlabPtr->feval(u"error", 
                0, std::vector<matlab::data::Array>({ factory.createScalar("Input must be m-by-n dimension") }));
        }
        
        if (inputs[2].getType() == matlab::data::ArrayType::DOUBLE ||
            inputs[2].getType() != matlab::data::ArrayType::COMPLEX_DOUBLE) {
            matlabPtr->feval(u"error", 
                0, std::vector<matlab::data::Array>({ factory.createScalar("Input idxtMTX must be type complex double") }));
        }

        if (inputs[2].getDimensions().size() != 2) {
            matlabPtr->feval(u"error", 
                0, std::vector<matlab::data::Array>({ factory.createScalar("Input must be m-by-n dimension") }));
        }

        // Check that the coherence matrix and phase vector are the same size in the first dimension
        if (inputs[1].getDimensions()[0] != inputs[2].getDimensions()[0]) {
            matlabPtr->feval(u"error", 
                0, std::vector<matlab::data::Array>({ factory.createScalar("Input coherence matrix and phase vector must be the same size in the first dimension") }));
        }

        // Check that the coherence matrix is square
        if (inputs[1].getDimensions()[0] != inputs[1].getDimensions()[1]) {
            matlabPtr->feval(u"error", 
                0, std::vector<matlab::data::Array>({ factory.createScalar("Input coherence matrix must be square") }));
        }
    }
    
    template <typename T>
    const T* getDataPtr(matlab::data::Array arr) {
        const matlab::data::TypedArray<T> arr_t = arr;
        matlab::data::TypedIterator<const T> it(arr_t.begin());
        return it.operator->();
    }
    
    template <typename T>
    T* getOutDataPtr(matlab::data::Array& arr) {
      auto range = matlab::data::getWritableElements<T>(arr);
      return range.begin().operator->();
    }

};