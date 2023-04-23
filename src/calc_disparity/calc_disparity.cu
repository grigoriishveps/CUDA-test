
#include "calc_disparity.cuh"

#define D_LVL 64

void calc_disparity(cost_3d_array &sum_cost, cv::Mat &disp_img, size_t rows, size_t cols) {
  for (int row = 0; row < rows; row++) {
    for (int col = D_LVL; col < cols; col++) {
      unsigned char min_depth = 0;
      unsigned long min_cost = sum_cost[row][col][min_depth];
      for (int d = 1; d < D_LVL; d++) {
        unsigned long tmp_cost = sum_cost[row][col][d];
        if (tmp_cost < min_cost) {
          min_cost = tmp_cost;
          min_depth = d;
        }
      }
      disp_img.at<unsigned char>(row, col) = min_depth;
    } 
  } 

  return;
}
