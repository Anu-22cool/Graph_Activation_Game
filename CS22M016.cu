/*
 * Title: CS6023, GPU Programming, Jan-May 2023, Assignment-3
 * Description: Activation Game 
 */

#include <cstdio>        // Added for printf() function 
#include <sys/time.h>    // Added to get time of day
#include <cuda.h>
#include <bits/stdc++.h>
#include <fstream>
#include "graph.hpp"
#define BlockSize 1024
 
using namespace std;


ofstream outfile; // The handle for printing the output

/******************************Write your kerenels here ************************************/

// in this function nodes are getting updated which are going to be in next level that is L+1 simultaneously gmax is getting set to the last node of that level 
//  so that we will get to know how much nodes are present in next level of the graph. 
__global__ void forth(int *csr_offset, int *csr_List, int *apr, int *aid, int *num_active, int *active, int *levels, int V, int E, int L,int l,int *gmax,int *gmin)
{
       int tid = threadIdx.x + blockIdx.x * blockDim.x+gmin[0];
    if(tid < V && levels[tid]==l)
        {   int from=csr_offset[tid],to= csr_offset[tid+1];
            int j=from;
            while(j<to)
            {
                levels[csr_List[j]] = l+1;
                atomicMax(&gmax[0], csr_List[j]);
                j++;
            }
        }
}

//in this function indegree of the the nodes present in level L+1 are incremented by the active nodes present in the level L. 
__global__ void third(int *csr_offset, int *csr_List, int *apr, int *aid, int *num_active, int *active, int *levels, int V, int E, int L,int l,int *gmax,int *gmin)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x+gmin[0];
    if(tid < V && levels[tid]==l && active[tid]==1)
    {
            int from=csr_offset[tid],to= csr_offset[tid+1];
            int j=from;
            while(j<to)
            {
                atomicAdd(&aid[csr_List[j]], 1);
                j++;
            }
    }
     
}


// in this kernel nodes which are active but there neighbours(left and right ones) are deactive and all three of them present in same level then then middle active node will
// get deactive
__global__ void second(int *csr_offset, int *csr_List, int *apr, int *aid, int *num_active, int *active, int *levels, int V, int E, int L,int l,int *gmax,int *gmin)
{
        int tid =threadIdx.x + blockIdx.x * blockDim.x+gmin[0];
       if(tid < V-1 && tid > 0 &&  active[tid] == 1 && levels[tid] == l)
         if( levels[tid-1] == l && active[tid-1] == 0 &&  levels[tid+1] == l &&  active[tid+1] == 0) 
                 {
                    atomicExch(&active[tid], 0);
                    atomicSub(&num_active[l], 1);                      
                 }

}


// in this function nodes whose activation point requirement is equal to the active in degree are getting updated  
__global__ void first(int *csr_offset, int *csr_List, int *apr, int *aid, int *num_active, int *active, int *levels, int V, int E, int L,int l,int *gmax,int *gmin)
{
        int tid = threadIdx.x + blockIdx.x * blockDim.x + gmin[0];
        if(tid < V && levels[tid] == l && aid[tid] >= apr[tid] && active[tid]==0)
        {
            atomicExch(&active[tid], 1);
            atomicAdd(&num_active[l], 1);
        }
        
}


// in this fucntion nodes of level 0 are getting updated and simultaneously we will set gmax equal to the number of nodes in level 0 .  
__global__ void ini_kernel( int *apr ,int *num_active, int *active, int *levels, int V,int *gmax)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    if(tid < V && apr[tid] == 0)
    {    
        active[tid]= 1;
        levels[tid]= 0;
        atomicAdd(&num_active[0], 1);
        atomicMax(&gmax[0], tid);
    }
}
    
    
/**************************************END*************************************************/



//Function to write result in output file
void printResult(int *arr, int V,  char* filename){
    outfile.open(filename);
    for(long int i = 0; i < V; i++){
        outfile<<arr[i]<<" ";   
    }
    outfile.close();
}

/**
 * Timing functions taken from the matrix multiplication source code
 * rtclock - Returns the time of the day 
 * printtime - Prints the time taken for computation 
 **/
double rtclock(){
    struct timezone Tzp;
    struct timeval Tp;
    int stat;
    stat = gettimeofday(&Tp, &Tzp);
    if (stat != 0) printf("Error return from gettimeofday: %d", stat);
    return(Tp.tv_sec + Tp.tv_usec * 1.0e-6);
}

void printtime(const char *str, double starttime, double endtime){
    printf("%s%3f seconds\n", str, endtime - starttime);
}

int main(int argc,char **argv){
    // Variable declarations
    int V ; // Number of vertices in the graph
    int E; // Number of edges in the graph
    int L; // number of levels in the graph

    //Reading input graph
    char *inputFilePath = argv[1];
    graph g(inputFilePath);

    //Parsing the graph to create csr list
    g.parseGraph();

    //Reading graph info 
    V = g.num_nodes();
    E = g.num_edges();
    L = g.get_level();


    //Variable for CSR format on host
    int *h_offset; // for csr offset
    int *h_csrList; // for csr
    int *h_apr; // active point requirement

    //reading csr
    h_offset = g.get_offset();
    h_csrList = g.get_csr();   
    h_apr = g.get_aprArray();
    
    
    // Variables for CSR on device
    int *d_offset;
    int *d_csrList;
    int *d_apr; //activation point requirement array
    int *d_aid; // acive in-degree array
    //Allocating memory on device 
    cudaMalloc(&d_offset, (V+1)*sizeof(int));
    cudaMalloc(&d_csrList, E*sizeof(int)); 
    cudaMalloc(&d_apr, V*sizeof(int)); 
    cudaMalloc(&d_aid, V*sizeof(int));

    //copy the csr offset, csrlist and apr array to device
    cudaMemcpy(d_offset, h_offset, (V+1)*sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_csrList, h_csrList, E*sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_apr, h_apr, V*sizeof(int), cudaMemcpyHostToDevice);

    // variable for result, storing number of active vertices at each level, on host
    int *h_activeVertex;
    h_activeVertex = (int*)malloc(L*sizeof(int));
    // setting initially all to zero
    memset(h_activeVertex, 0, L*sizeof(int));

    // variable for result, storing number of active vertices at each level, on device
    int *d_activeVertex;
	  cudaMalloc(&d_activeVertex, L*sizeof(int));


/***Important***/

// Initialize d_aid array to zero for each vertex
// Make sure to use comments

/***END***/
double starttime = rtclock(); 

/*********************************CODE AREA*****************************************/
cudaMemset(d_aid, 0, V*sizeof(int));
cudaMemcpy(d_activeVertex, h_activeVertex, L*sizeof(int), cudaMemcpyHostToDevice);
int *d_active;
cudaMalloc(&d_active, V*sizeof(int));
cudaMemset(d_active, 0, V*sizeof(int));
int *d_levels;
cudaMalloc(&d_levels, V*sizeof(int));
cudaMemset(d_levels, -1, V*sizeof(int));
int grid_size = ceil((float)V / 1024);


int cmax[1],*gmax,cmin[1],*gmin;
cmax[0]=0;
cmin[0]=0;
// cmax is the last node of that level and cmin is the first node of that level in cpu.
// gmax is the last node of that level and gmin is the first node of that level in gpu.
cudaMalloc(&gmax,sizeof(int));
cudaMalloc(&gmin,sizeof(int));
cudaMemcpy(gmax , cmax, sizeof(int), cudaMemcpyHostToDevice);
cudaMemcpy(gmin , cmin, sizeof(int), cudaMemcpyHostToDevice);

//( int *apr ,int *num_active, int *active, int *levels, int V,int *gmax)
ini_kernel<<<grid_size,1024>>>(d_apr,d_activeVertex,d_active,d_levels,V,gmax);
cudaMemcpy(cmax , gmax, sizeof(int), cudaMemcpyDeviceToHost);
printf("%d",cmax[0]);
int l=0;
    while(l<L)
    {  

       grid_size= ceil((float)(cmax[0]-cmin[0]+1)/1024);
      first<<<grid_size,1024>>>(d_offset,d_csrList,d_apr,d_aid,d_activeVertex,d_active,d_levels,V,E,L,l,gmax,gmin);     
      second<<<grid_size,1024>>>(d_offset,d_csrList,d_apr,d_aid,d_activeVertex,d_active,d_levels,V,E,L,l,gmax,gmin);
      third<<<grid_size,1024>>>(d_offset,d_csrList,d_apr,d_aid,d_activeVertex,d_active,d_levels,V,E,L,l,gmax,gmin);
      forth<<<grid_size,1024>>>(d_offset,d_csrList,d_apr,d_aid,d_activeVertex,d_active,d_levels,V,E,L,l,gmax,gmin);
      cmin[0]=cmax[0];
      cudaMemcpy(cmax , gmax, sizeof(int), cudaMemcpyDeviceToHost);
      cudaMemcpy(gmin , cmin, sizeof(int), cudaMemcpyHostToDevice);

      l++;
    }
cudaMemcpy(h_activeVertex, d_activeVertex, L*sizeof(int), cudaMemcpyDeviceToHost);
/********************************END OF CODE AREA**********************************/
double endtime = rtclock();  
printtime("GPU Kernel time: ", starttime, endtime);  

// --> Copy C from Device to Host
char outFIle[30] = "./output.txt" ;
printResult(h_activeVertex, L, outFIle);
if(argc>2)
{
    for(int i=0; i<L; i++)
    {
        printf("level = %d , active nodes = %d\n",i,h_activeVertex[i]);
    }
}

    return 0;
}
