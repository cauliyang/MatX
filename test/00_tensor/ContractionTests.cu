////////////////////////////////////////////////////////////////////////////////
// BSD 3-Clause License
//
// Copyright (c) 2021, NVIDIA Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
/////////////////////////////////////////////////////////////////////////////////

#include "assert.h"
#include "matx.h"
#include "test_types.h"
#include "utilities.h"
#include "gtest/gtest.h"
#include "matx_pybind.h"
#include "matx_einsum.h"

using namespace matx;

template <typename TensorType> struct ContractionTestsData {
  tensor_t<TensorType, 0> t0{};
  tensor_t<TensorType, 1> t1{{10}};
  tensor_t<TensorType, 2> t2{{20, 10}};
  tensor_t<TensorType, 3> t3{{30, 20, 10}};
  tensor_t<TensorType, 4> t4{{40, 30, 20, 10}};

  tensor_t<TensorType, 2> t2s = t2.Permute({1, 0});
  tensor_t<TensorType, 3> t3s = t3.Permute({2, 1, 0});
  tensor_t<TensorType, 4> t4s = t4.Permute({3, 2, 1, 0});
};

template <typename TensorType>
class ContractionTestsComplex : public ::testing::Test,
                                public ContractionTestsData<TensorType> {
};
template <typename TensorType>
class ContractionTestsFloat : public ::testing::Test,
                              public ContractionTestsData<TensorType> {
};
template <typename TensorType>
class ContractionTestsFloatNonComplex
    : public ::testing::Test,
      public ContractionTestsData<TensorType> {
};
template <typename TensorType>
class ContractionTestsNumeric : public ::testing::Test,
                                public ContractionTestsData<TensorType> {
};
template <typename TensorType>
class ContractionTestsNumericNonComplex
    : public ::testing::Test,
      public ContractionTestsData<TensorType> {
};
template <typename TensorType>
class ContractionTestsIntegral : public ::testing::Test,
                                 public ContractionTestsData<TensorType> {
};
template <typename TensorType>
class ContractionTestsBoolean : public ::testing::Test,
                                public ContractionTestsData<TensorType> {
};
template <typename TensorType>
class ContractionTestsAll : public ::testing::Test,
                            public ContractionTestsData<TensorType> {
};

TYPED_TEST_SUITE(ContractionTestsAll, MatXAllTypes);
TYPED_TEST_SUITE(ContractionTestsComplex, MatXComplexTypes);
TYPED_TEST_SUITE(ContractionTestsFloat, MatXFloatTypes);
TYPED_TEST_SUITE(ContractionTestsFloatNonComplex, MatXFloatNonComplexTypes);
TYPED_TEST_SUITE(ContractionTestsNumeric, MatXNumericTypes);
TYPED_TEST_SUITE(ContractionTestsIntegral, MatXAllIntegralTypes);
TYPED_TEST_SUITE(ContractionTestsNumericNonComplex, MatXNumericNonComplexTypes);
TYPED_TEST_SUITE(ContractionTestsBoolean, MatXBoolTypes);

#if ENABLE_CUTENSOR
TEST(ContractionTests, BasicRealFloat)
{
  MATX_ENTER_HANDLER();
  using TypeParam = float;

  auto pb = std::make_unique<detail::MatXPybind>();
  pb->template InitAndRunTVGenerator<float>(
      "00_operators", "contraction", "run", {});  

  {
    // 3D contraction on two dimensions
    auto a1 = make_tensor<float>({60});
    auto b1 = make_tensor<float>({24});
    auto c2 = make_tensor<float>({5,2});

    (a1 = linspace<0>(a1.Shape(), 0.0f, static_cast<float>(a1.Size(0) - 1))).run();
    (b1 = linspace<0>(b1.Shape(), 0.0f, static_cast<float>(b1.Size(0) - 1))).run();
    auto a = a1.View({3,4,5});
    auto b = b1.View({4,3,2});

    cutensor::einsum(c2, "ijk,jil->kl", 0, a, b);
    cudaStreamSynchronize(0);
    MATX_TEST_ASSERT_COMPARE(pb, c2, "c_float3d", 0.01);
  }

  {
    // Dot
    auto a1 = make_tensor<float>({60});
    auto b1 = make_tensor<float>({60});
    auto c0 = make_tensor<float>();
    (a1 = ones(a1.Shape()) * 2).run();
    (b1 = ones(b1.Shape()) * 2).run(); 
    cutensor::einsum(c0, "i,i->", 0, a1, b1);   
    cudaStreamSynchronize(0);
    MATX_ASSERT_EQ(c0(), 4 * a1.Size(0));
  }

  {
    // GEMM
    auto a2 = make_tensor<float>({10,20});
    auto b2 = make_tensor<float>({20,10});
    auto c2 = make_tensor<float>({10,10});    
    auto c22 = make_tensor<float>({10,10});   
    (a2 = ones(a2.Shape())).run();
    (b2 = ones(b2.Shape())).run(); 

    cutensor::einsum(c2, "mk,kn->mn", 0, a2, b2);
    matmul(c22, a2, b2);
    cudaStreamSynchronize(0);

    for (auto i = 0; i < c2.Size(0); i++) {
      for (auto j = 0; j < c2.Size(1); j++) {
        MATX_ASSERT_EQ(c2(i,j), c22(i,j));
      }
    }
  }

  {
    // GEMM with transpose
    auto a2 = make_tensor<float>({5,20});
    auto b2 = make_tensor<float>({20,10});
    auto c2 = make_tensor<float>({10,5});    
    auto c22 = make_tensor<float>({5,10});   
    (a2 = ones(a2.Shape())).run();
    (b2 = ones(b2.Shape())).run(); 

    cutensor::einsum(c2, "mk,kn->nm", 0, a2, b2);
    matmul(c22, a2, b2);
    cudaStreamSynchronize(0);

    auto c22t = c22.Permute({1,0}); // Permute to match cutensor

    for (auto i = 0; i < c2.Size(0); i++) {
      for (auto j = 0; j < c2.Size(1); j++) {
        MATX_ASSERT_EQ(c2(i,j), c22t(i,j));
      }
    }
  } 


  MATX_EXIT_HANDLER();
}
#endif