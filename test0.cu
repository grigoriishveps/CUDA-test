#include <iostream>
#include <fstream>
#include <string>
#include <stdexcept>
#include "opencv2/opencv.hpp"

typedef std::vector<std::vector<std::vector<unsigned long> > > cost_3d_array;
typedef std::vector<std::vector<std::vector<std::vector<unsigned long> > > > cost_4d_array;

using namespace std; 

class ScanLine {
public:
  ScanLine(int drow, int dcol, bool posdir) {
    this->drow = drow;
    this->dcol = dcol;
    this->posdir = posdir;
  }
  bool posdir;
  int drow, dcol;
};

#define D_LVL 64

class ScanLines8 {
public:
  ScanLines8() {
    this->path8.push_back(ScanLine(1, 1, true));
    this->path8.push_back(ScanLine(1, 0, true));
    this->path8.push_back(ScanLine(1, -1, true));
    this->path8.push_back(ScanLine(0, -1, false));
    // this->path8.push_back(ScanLine(-1, -1, false));
    // this->path8.push_back(ScanLine(-1, 0, false));
    // this->path8.push_back(ScanLine(-1, 1, false));
    this->path8.push_back(ScanLine(0, 1, true));
  }
  
  std::vector<ScanLine> path8;
};

class Sgbm {

public:
  Sgbm(int rows, int cols, unsigned short p1=0, 
  unsigned short p2 =0, bool gauss_filt = false, bool show_res = false);

  ~Sgbm();
  void reset_buffer();

  void compute_disp(cv::Mat &left, cv::Mat &right, cv::Mat &disp);

  unsigned short aggregate_cost(int row, int col, int depth, int path, cost_3d_array &pix_cost, cost_4d_array &agg_cost);

  void aggregate_cost_for_each_scanline(cost_3d_array &pix_cost, cost_4d_array &agg_cost, cost_3d_array &sum_cost);

  void calc_disparity(cost_3d_array &sum_cost, cv::Mat &disp_img);

  void census_transform(cv::Mat &img, cv::Mat &census);

  void calc_pixel_cost(cv::Mat &census_l, cv::Mat &census_r, cost_3d_array &pix_cost);

  unsigned char calc_hamming_dist(unsigned char val_l, unsigned char val_r);

public:

  bool gauss_filt, show_res;
  int rows, cols, scanpath;
  unsigned short p1, p2;
  cv::Mat *census_l, *census_r, *disp_img;
  cost_3d_array pix_cost;
  cost_4d_array agg_cost;
  cost_3d_array sum_cost;
  ScanLines8 scanlines;
};

Sgbm::Sgbm(int rows, int cols, unsigned short p1, 
  unsigned short p2, bool gauss_filt, bool show_res) {

  this->rows = rows;
  this->cols = cols;
  this->census_l = new cv::Mat(rows, cols, CV_8UC1);
  this->census_r = new cv::Mat(rows, cols, CV_8UC1);
  this->disp_img = new cv::Mat(rows, cols, CV_8UC1);
  this->p1 = p1;
  this->p2 = p2;
  this->scanpath = 8;
  this->gauss_filt = gauss_filt;
  this->show_res = show_res;

  reset_buffer();
}

Sgbm::~Sgbm() 
{
  delete this->census_l;
  delete this->census_r;
}


void Sgbm::compute_disp(cv::Mat &left, cv::Mat &right, cv::Mat &disp)
{

  // 0. Reset Buffer.
  reset_buffer();

  // if (this->gauss_filt) {
  //   cv::GaussianBlur(left, left, cv::Size(3, 3), 3);
  //   cv::GaussianBlur(right, right, cv::Size(3, 3), 3);
  // }

  if (this->show_res) {
    cv::imshow("Left Original", left);
    cv::imshow("Right Original", right);
    // cv::waitKey(0);
  }

  // 1. Census Transform.
  cout << "1. Census Transform" << endl;
  census_transform(left, *this->census_l);
  census_transform(right, *this->census_r);


  if (this->show_res) {
    cv::imshow("Census Trans Left", *this->census_l);
    cv::imshow("Census Trans Right", *this->census_r);
    // cv::waitKey(0);
  }

  // 2. Calculate Pixel Cost.
  cout << "2. Calculate Pixel Cost." << endl;
  calc_pixel_cost(*this->census_l, *this->census_r, this->pix_cost);
    for (int col = 0; col < 70; col++) {
        cout << this->pix_cost[100][col][5] << " " ;
    }

    cout  << endl ;

  // 3. Aggregate Cost
  cout << "3. Aggregate Cost" << endl;
  aggregate_cost_for_each_scanline(this->pix_cost, this->agg_cost, this->sum_cost);

  // 4. Create Disparity Image.
  cout << "4. Create Disparity Image." << endl;
  calc_disparity(this->sum_cost, *this->disp_img);

  // Visualize Disparity Image.
  disp = *this->disp_img;

  if (this->show_res) {
    cv::Mat tmp;
    disp.convertTo(tmp, CV_8U, 256.0/D_LVL);
    applyColorMap(tmp, tmp, cv::COLORMAP_JET);
    cv::imshow("Sgbm Result", tmp);
    cv::waitKey(0);
  }

  return;
}

void Sgbm::reset_buffer() 
{

  *(this->census_l) = 0;
  *(this->census_r) = 0;

  // Resize vector for Pix Cost
  this->pix_cost.resize(this->rows);
  this->sum_cost.resize(this->rows);
  for (int row = 0; row < this->rows; row++) {
    this->pix_cost[row].resize(this->cols);
    this->sum_cost[row].resize(this->cols);
    for (int col = 0; col < this->cols; col++) {
      this->pix_cost[row][col].resize(D_LVL, 0x0000);
      this->sum_cost[row][col].resize(D_LVL, 0x0000);
    }
  }

  // Resize vector for Agg Cost
  this->agg_cost.resize(this->scanpath);
  for (int path = 0; path < this->scanpath; path++) {
    this->agg_cost[path].resize(this->rows);
    for (int row = 0; row < this->rows; row++) {
      this->agg_cost[path][row].resize(this->cols);
      for (int col = 0; col < this->cols; col++) {
        this->agg_cost[path][row][col].resize(D_LVL, 0x0000);
      }
    }
  }

  return;
}

void Sgbm::census_transform(cv::Mat &img, cv::Mat &census){
  unsigned char * const img_pnt_st = img.data;
  unsigned char * const census_pnt_st = census.data;

  for (int row=1; row<rows-1; row++) {
    for (int col=1; col<cols-1; col++) {

      unsigned char *center_pnt = img_pnt_st + cols*row + col;
      unsigned char val = 0;
      for (int drow=-1; drow<=1; drow++) {
        for (int dcol=-1; dcol<=1; dcol++) {
          
          if (drow == 0 && dcol == 0) {
            continue;
          }
          unsigned char tmp = *(center_pnt + dcol + drow*cols);
          val = (val + (tmp < *center_pnt ? 0 : 1)) << 1;        
        }
      }
      *(census_pnt_st + cols*row + col) = val;
    }
  }
  return;
}

void Sgbm::calc_pixel_cost(cv::Mat &census_l, cv::Mat &census_r, cost_3d_array &pix_cost) {

  unsigned char * const census_l_ptr_st = census_l.data;
  unsigned char * const census_r_ptr_st = census_r.data;

  for (int row = 0; row < this->rows; row++) {
    for (int col = 0; col < this->cols; col++) {
      unsigned char val_l = static_cast<unsigned char>(*(census_l_ptr_st + row*cols + col));
      for (int d = 0; d < D_LVL; d++) {
        unsigned char val_r = 0;
        if (col - d >= 0) {
          val_r = static_cast<unsigned char>(*(census_r_ptr_st + row*cols + col - d));
        }
        pix_cost[row][col][d] = calc_hamming_dist(val_l, val_r);
      }
    }
  }
}

unsigned char Sgbm::calc_hamming_dist(unsigned char val_l, unsigned char val_r) {

  unsigned char dist = 0;
  unsigned char d = val_l ^ val_r;

  while(d) {
    d = d & (d - 1);
    dist++;
  }
  return dist;  
}

unsigned short Sgbm::aggregate_cost(int row, int col, int depth, int path, cost_3d_array &pix_cost, cost_4d_array &agg_cost) {
  // Depth loop for current pix.
  unsigned long val0 = 0xFFFF, val1 = 0xFFFF, val2 = 0xFFFF, val3 = 0xFFFF;
  unsigned long min_prev_d = 0xFFFF;

  int dcol = this->scanlines.path8[path].dcol;
  int drow = this->scanlines.path8[path].drow;

  // Pixel matching cost for current pix.
  unsigned long indiv_cost = pix_cost[row][col][depth];

  if (row - drow < 0 || this->rows <= row - drow || col - dcol < 0 || this->cols <= col - dcol) {
    agg_cost[path][row][col][depth] = indiv_cost;
    return agg_cost[path][row][col][depth];
  }

  // Depth loop for previous pix.
  for (int dd = 0; dd < D_LVL; dd++) {
    unsigned long prev = agg_cost[path][row-drow][col-dcol][dd];
    if (prev < min_prev_d) {
      min_prev_d = prev;
    }
    
    if (depth == dd) {
      val0 = prev;
    } else if (depth == dd + 1) {
      val1 = prev + this->p1;
    } else if (depth == dd - 1) {
      val2 = prev + this->p1;
    } else {
      unsigned long tmp = prev + this->p2;
      if (tmp < val3) {
        val3 = tmp;
      }            
    }
  }

  // Select minimum cost for current pix.
  agg_cost[path][row][col][depth] = std::min(std::min(std::min(val0, val1), val2), val3) + indiv_cost - min_prev_d;
  //agg_cost[path][row][col][depth] = indiv_cost;

  return agg_cost[path][row][col][depth];
}

void Sgbm::aggregate_cost_for_each_scanline(cost_3d_array &pix_cost, cost_4d_array &agg_cost, cost_3d_array &sum_cost)
{
  // Cost aggregation for positive direction.
  for (int row = 0; row < this->rows; row++) {
    for (int col = 0; col < this->cols; col++) {
      for (int path = 0; path < this->scanlines.path8.size(); path++) {
        if (this->scanlines.path8[path].posdir) {
          //std::cout << "Pos : " << path << std::endl;
          for (int d = 0; d < D_LVL; d++) {
            sum_cost[row][col][d] += aggregate_cost(row, col, d, path, pix_cost, agg_cost);
          }
        }
      }
    }
  }

  // Cost aggregation for negative direction.
  for (int row = this->rows - 1; 0 <= row; row--) {
    for (int col = this->cols - 1; 0 <= col; col--) {
      for (int path = 0; path < this->scanlines.path8.size(); path++) {
        if (!this->scanlines.path8[path].posdir) {
          //std::cout << "Neg : " << path << std::endl;
          for (int d = 0; d < D_LVL; d++) {
            sum_cost[row][col][d] += aggregate_cost(row, col, d, path, pix_cost, agg_cost);
          }
        }
      }
    }
  }
  return;
}

void Sgbm::calc_disparity(cost_3d_array &sum_cost, cv::Mat &disp_img){
  for (int row = 0; row < this->rows; row++) {
    for (int col = 0; col < this->cols; col++) {
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

int main(int argc, char** argv) {
  std::cout << "SGBM Test Started!" << std::endl;
  std::string left_path = "leftImage1.png",
    right_path = "rightImage1.png";
  
  int p1 = 3, p2 = 20;

  std::cout << "1. Open and load images" << std::endl;
  cv::Mat left = cv::imread(left_path, cv::IMREAD_GRAYSCALE);
  cv::Mat right = cv::imread(right_path, cv::IMREAD_GRAYSCALE);

  std::cout << "2. Initialize class" << std::endl;
  Sgbm sgbm(left.rows, left.cols, p1, p2, false, true);
  cv::Mat disp;
  
  compute_disp(left, right, disp);


  cout << "" << endl;
  while(1)
    {
        short key = (short) cv::waitKey();
        if( key == 27 || key == 'q' || key == 'Q') // 'ESC'
            break;
    }
  return 0;
}