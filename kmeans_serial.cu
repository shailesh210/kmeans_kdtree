// K-means clustering algorithm. Implementaion using kd-tree
// Author: Shailesh Tripathi

#include <iostream>
#include <vector>
#include <float.h>
#include <math.h>
#include <algorithm>
#include <fstream>
#include <thrust/host_vector.h>
#include <thrust/device_vector.h>
#include <thrust/extrema.h>

using namespace std;

//global device variables
double *d_C_x, *d_C_y;


//global variables to keep track of the leaf nodes
//Equally distributed leaf nodes will be selected as initial centroids
int total_leafs; 

//utility function to compute euclidean distance between two vectors
double calc_dist(vector<double> &A, vector<double> &B)
{
	if(A.size() != B.size())
	{
		cout<<A.size()<<' '<<B.size()<<"Invalid calculation of distance vectors\n";
		return 0;
	} 
	double res = 0;
	for(int i=0;i<A.size();i++)
		res += ((A[i]-B[i]) * (A[i]-B[i]));

	res = sqrt(res);
	return res;
}

__device__
double calc_dist_xy(double x1, double y1, double x2, double y2)
{
	double x = x1 - x2;
	double y = y1 - y2;
	return sqrt(x*x + y*y);
}

//utility [A] = [A] + [B]
void add_vec(vector<double> &A, vector<double> &B)
{
	if(A.size() != B.size())
	{
		cout<<A.size()<<' '<<B.size()<<"Invalid addition of vectors\n";
		return ;
	} 
	for(int i=0;i<A.size();i++)
	{
		A[i]+=B[i];
	}
	return ;
}

class Point
{
	public:
		int id_point, id_cluster;
	    vector<double> values;
   		int dimension;
		
	Point(int id_point, vector<double>& values)
    {
        this->id_point = id_point;
        dimension = values.size();

        for(int i = 0; i < dimension; i++)
            this->values.push_back(values[i]);

        id_cluster = -1;
    }
	
};

class Data_tree
{
	public:
		Data_tree *left, *right;
		vector<Point> points;
		vector<double> min_C, max_C;
		vector<double> mid_C,wgt_cent;
		int num_points;
		

		Data_tree(vector<Point> P)
		{
			points = P;
			left=NULL;
			right=NULL;
			num_points = P.size();
			int i,j;
			if(P.size() != 0)
			{
			
				//initialize min, max nad mid for each dimension	
				for(i = 0 ; i<P[0].dimension ; i++)
				{
					min_C.push_back(DBL_MAX);
					max_C.push_back(DBL_MIN);
					mid_C.push_back(0);
				}

				for(i = 0 ; i<P.size() ; i++)
				{
					for(j=0;j<P[i].dimension;j++)
					{
						min_C[j] = min(min_C[j], P[i].values[j]);
						max_C[j] = max(max_C[j], P[i].values[j]);
						mid_C[j] += P[i].values[j];
					}
				}
				wgt_cent = mid_C;
				for(i = 0 ; i<P[0].dimension ; i++)	
				{
					
					mid_C[i] /= P.size();
				} 
			}
		}

		void display()
		{
			//cout<<"size="<<points.size()<<endl;
			for(int j=0;j< points.size();j++)
			{
				for(int i=0;i < points[j].values.size();i++)
					cout<<points[j].values[i]<<' ';
				cout<<endl;
			}

		}

};

class Centroid
{
	public:
		vector<double> values;
		vector<double> center_sum;
		int count;
		int cent_id;
		int dimension;
	Centroid()
	{
//		values = C;
//		center_sum = 0;
		count = 0;
	}

	Centroid(int dim,int id)
	{
		dimension = dim;
		cent_id = id;
		count = 0;
		center_sum = vector<double>(dim,0);
	}	

	bool update()
	{	
		bool res =0;
		if(count != 0)
		{
			for(int i=0 ; i<center_sum.size();i++)
			{
				if( values[i] != center_sum[i]/count)
					res = 1;
				values[i] = center_sum[i]/count;
				center_sum[i] = 0;
			}
		count = 0;
		}
		return res;
	}
};

void print(vector<Point> P, int total_attributes)
{
	int i,j;
	for( i = 0 ; i < P.size() ; i++ )
	{
		for( j=0 ; j<total_attributes ; j++)
			cout<<P[i].values[j]<<' ';
		cout << endl;
	}
}

double find_median(vector<Point> P, int dim, int &status)
{
	vector<double> M;
	double median;

	for(int i=0; i< P.size() ;i++)
	{
		M.push_back(P[i].values[dim]);
	}
	sort(M.begin(), M.end());
	median = M[M.size()/2];

	if( M[0] == M.back())
		status = -1;
else
		status = ((median == M[0]) ? 0:1); //0- left ; 1- right
	
	return median;
}

void make_tree(Data_tree **node, vector<Point> P, int dim, int total_attributes)
{
	if(P.size() == 0)
		return;	
	int status;
	//print(P,total_attributes);	
	cout<<"points size = "<<P.size()<<' '<<dim<<'\n';
	*node = new Data_tree(P);
//	(*node)->display();
	if( P.size() == 1)
	{
		total_leafs++;
		return;
	}

	int initial_dim = dim;
	double median;
	do{
		median = find_median(P, dim,status);
		dim = (dim+1)%total_attributes;
	}while(status== -1 && dim!=initial_dim);
	
	if(dim == initial_dim)	//all the points in the node are same.
							//Therefore we don't break it further.
	{
		total_leafs++;
		return;
	}
	
	//Get the dimension where we actuallly broke
	dim = (dim + total_attributes - 1)% total_attributes;
	
	vector<Point> L,R;
	if(status == 0 )
	{
		for(int i=0; i< P.size() ;i++)
		{
			if(P[i].values[dim] <= median)
				L.push_back(P[i]);
			else
				R.push_back(P[i]);
		}
	}
	else
	{
		for(int i=0; i< P.size() ;i++)
		{
			if(P[i].values[dim] < median)
				L.push_back(P[i]);
			else
				R.push_back(P[i]);
		}
	}


	make_tree(&((*node)->left), L, (dim+1)%total_attributes, total_attributes);
	make_tree(&((*node)->right), R, (dim+1)%total_attributes, total_attributes);
}

void iterate_tree(Data_tree *node, int total_attributes, int &skip, int &leaf_id, int &K, vector<Centroid> &C)
{
	if( node == NULL ) 
	{
//		cout<<endl;
		return;
	}
	
	if(node->left == NULL && node->right == NULL) //leaf node 
	{
		leaf_id++;
//		cout<<leaf_id<<' '<<skip<<'\n';
		if(leaf_id % skip ==0 && leaf_id/skip < K) 
		{
//			cout<<leaf_id/skip<<' ';
			Centroid temp(total_attributes, leaf_id/skip);
			temp.values = node->mid_C;
//			cout<<"values size = "<<temp.values.size()<<endl;
			C.push_back(temp);
		}
	}
//	cout<<"min-max-mid\n";	
//	for(int i=0;i<total_attributes;i++)
//	{
//		cout<<node->min_C[i] << ' '<<node->max_C[i]<<' '<<node->mid_C[i]<<endl;
//	}
//
//	cout<<"enter\n";
//	for(int i=0; i< node->points.size() ;i++)
//	{
//		for(int j=0; j <total_attributes; j++)
//			cout<< node->points[i].values[j]<<' ';
//		cout<<endl;
//	}
	iterate_tree(node->left, total_attributes,skip, leaf_id, K, C);
	iterate_tree(node->right, total_attributes,skip, leaf_id, K, C);
	
//	cout<<"exit\n";
}

//returns true if z is farther than z* (z is a not potential center)
bool isFarther(Data_tree *root, Centroid z, Centroid z_star)
{
	int dim = root->points[0].dimension;
	int i;
	vector<double> corner_point(dim);
	
	//cout<<"corner ";
	for(i=0;i<dim;i++)
	{
		if(z.values[i] > z_star.values[i] ) 
			corner_point[i] = root->max_C[i];
		else
			corner_point[i] = root->min_C[i];
	
	//	cout<<corner_point[i] <<' '<<z_star.values[i]<<' '<< z.values[i]<<endl;
	}
	//cout<<endl;
	
	//cout<< calc_dist(corner_point,z.values) <<' '<< calc_dist(corner_point,z_star.values) << endl;	
	return calc_dist(corner_point,z.values) > calc_dist(corner_point,z_star.values);

}


__device__
//returns true if z is farther than z* (z is a not potential center)
bool isFarther_vector(double* root_max_C, double* root_min_C , double z_x, double z_y, double z_star_x, double z_star_y)
{
	int dim =2;// root->points[0].dimension;
	int i;
	double corner_point_x, corner_point_y;
	
	//cout<<"corner ";
//	for(i=0;i<dim;i++)
		if(z_x > z_star_x ) 
			corner_point_x = root_max_C[0];
		else
			corner_point_x = root_min_C[0];
	
	//	cout<<corner_point[i] <<' '<<z_star.values[i]<<' '<< z.values[i]<<endl;
	//cout<<endl;
		if(z_y > z_star_y ) 
			corner_point_y = root_max_C[1];
		else
			corner_point_y = root_min_C[1];
	
	//	cout<<corner_point[i] <<' '<<z_star.values[i]<<' '<< z.values[i]<<endl;
	
	
	//cout<< calc_dist(corner_point,z.values) <<' '<< calc_dist(corner_point,z_star.values) << endl;	
	return  calc_dist_xy(corner_point_x, corner_point_y, z_x, z_y) > calc_dist_xy(corner_point_x, corner_point_y, z_star_x, z_star_y);

}

//CUDA kernel
__global__ void select_possible_centroids(double* root_max_C, double* root_min_C, bool* d_temp_id, int* ids, int num_ids, double* d_C_x, double* d_C_y, int z_star)
{
	int t_id = blockIdx.x * blockDim.x + threadIdx.x;
	if(t_id < num_ids && t_id!= z_star)
	{
		if(!isFarther_vector(root_max_C, root_min_C, d_C_x[ids[t_id]], d_C_y[ids[t_id]], d_C_x[ids[z_star]], d_C_y[ids[t_id]]))
		{
			d_temp_id[t_id]=1;		
		}
	}
}


void prune(Data_tree *node,vector<Centroid>& C, vector<int> ids)
{
	if (node == NULL)
		return;
//cout<<"enter pruning\n";	
	vector<int> pruned_id;
	int i,j;

	double dist,min_dist = DBL_MAX;
	int min_id;
	vector<double> corner(node->points.size());
	thrust::host_vector<double> h_Distance(ids.size());
	
	
	//CUDA - implement on device
	//find z*
	for(i =0; i < ids.size();i++)
	{
//		cout<<"cal dist_sizes "<<node->mid_C.size() << ' ' <<ids[i]<< ' '<< C[ids[i]].values.size()<<endl;
		h_Distance[i] =calc_dist(node->mid_C ,C[ids[i]].values);
	}
//		cout<<dist<<' ';

/*	 	if(dist < min_dist)
		{
			min_dist = dist;
			min_id = ids[i];
		}
*/
	
//	cout<<endl;

	//device
	thrust::device_vector<double> d_Distance = h_Distance;
    thrust::device_vector<double>::iterator iter = thrust::min_element(d_Distance.begin(), d_Distance.end());
	
	min_dist = *iter;
	min_id = ids[iter-d_Distance.begin()];
//cout<<"min_dist =" <<min_dist<<endl;	
	//if node is a leaf
	if(node->num_points == 1)
	{
		//add weights and centroid properties
		add_vec(C[min_id].center_sum, node->wgt_cent); 	//vector sum
		C[min_id].count += node->num_points;
		return;
	}

//	pruned_id.push_back(min_id);

	bool h_temp_id[ids.size()]={0};
	h_temp_id[iter-d_Distance.begin()] = 1;
	
	//device variables
	int *d_ids;
	bool *d_temp_id;
	double *d_root_max_C, *d_root_min_C;
	
	//allocate device memory
	cudaMalloc((void**)&d_ids, ids.size()*sizeof(int));
	cudaMalloc((void**)&d_temp_id, ids.size());
	cudaMalloc((void**)&d_root_max_C, node->max_C.size()*sizeof(double));
	cudaMalloc((void**)&d_root_min_C, node->min_C.size()*sizeof(double));


	//copy data to device
	cudaMemcpy(d_ids,     &(ids.front()), ids.size()*sizeof(int), cudaMemcpyHostToDevice);
	cudaMemcpy(d_temp_id, h_temp_id, ids.size(), cudaMemcpyHostToDevice);
	cudaMemcpy(d_root_max_C, &(node->max_C.front()), node->max_C.size()*sizeof(double), cudaMemcpyHostToDevice);
	cudaMemcpy(d_root_min_C, &(node->min_C.front()), node->min_C.size()*sizeof(double), cudaMemcpyHostToDevice);

	//assume there are just 2 dimensions
	// data to be sent : node_min_C[dim], node_max_C[dim	
	//CUDA - do this selection on device	
	select_possible_centroids<<<1,ids.size()>>>(d_root_max_C, d_root_min_C, d_temp_id, d_ids, ids.size(), d_C_x, d_C_y, iter-d_Distance.begin());

	cudaMemcpy(h_temp_id, d_temp_id, ids.size(), cudaMemcpyDeviceToHost);

	for(i=0; i<ids.size();i++)
	{
//		cout<<i<<' '<<h_temp_id[i]<<endl;
		if(h_temp_id[i]==1)
			pruned_id.push_back(ids[i]);
	}
/*	for(i=0;i<ids.size();i++)
	{
		if(ids[i]!=min_id)
		{
			if(! isFarther(node, C[ids[i]], C[min_id] ))
			{
				pruned_id.push_back(ids[i]);
			}
		}
		
	}
*/	
	
	cudaFree(d_ids);
	cudaFree(d_temp_id);
	cudaFree(d_root_max_C);
	cudaFree(d_root_min_C);
	//if only one centroid left
	if(pruned_id.size() == 1)
	{
		//add weights and centroid properties
		add_vec(C[min_id].center_sum, node->wgt_cent);	//vector sum
		C[min_id].count += node->num_points;
	}
	else
	{
		prune(node->left , C, pruned_id);
		prune(node->right, C, pruned_id);
	} 

}	

//utility function to print centroids
void print_centroid_details(vector<Centroid> &C)
{
	cout<<"Printing centroids "<<C.size()<<endl;
	for(int i=0; i <C.size();i++)
	{
		cout<<C[i].cent_id << ' '<< C[i].count<<' '<<C[i].values.size()<<endl;
		for(int j=0;j<C[i].center_sum.size();j++)
			cout<<C[i].values[j]<<' ';
		cout<<endl<<endl;
	}
}

bool update_centroid(vector<Centroid> &C)
{
	int i;
	bool res = 0;
	for(i=0;i<C.size();i++)
	{
		res |= C[i].update();
	}
	return res;
}

int main(int argc, char* argv[])
{

	if(argc != 2)
	{
		cout<<"Invalid parameters!\n";
		return 0;
	}

	int  total_points,		//total number of points
		 total_attributes,  //dimension
		 K,					//number of clusters
		 max_iterations;	//maximum number of iterations
	
	bool is_change;
	int i,j,iter;
	double value;
	Data_tree *root = NULL;
	ifstream fin;
	fin.open(argv[1]);
	fin >> total_points >> total_attributes >> K >> max_iterations;

	vector<Centroid> C;
	vector<Point> P;
	vector<double> values(total_attributes);

	//input the data points
	for(i = 0; i < total_points; i++)
	{

		for(j = 0; j < total_attributes; j++)
		{
			fin >> values[j];
		}

		Point p(i, values);
		P.push_back(p);
	}
	
	total_leafs = 0;
	//build the data tree
	make_tree(&root, P, 0, total_attributes);
	cout<<"total leafs = "<<total_leafs<<endl;
	int skip = total_leafs/K;
	int leaf_id = -1;

	//if K is less than leafs(less number of disctinct points than K
	if( K > total_leafs)
	{
		K=total_leafs;
	}
	
	//iterate over the tree and print it
	iterate_tree(root, total_attributes,skip,leaf_id, K, C);

//	print_centroid_details(C);
	
	//using test centers
	/*Centroid temp;
	vector<double> L(2);
	vector<double> zero_vec(2,0);
	L[0] = 2;
	L[1] = 2;
	
	temp.values = L;
	temp.cent_id = 0;
	temp.center_sum = zero_vec;
	C.push_back(temp);
		
	L[0] = 4;
	L[1] = 4;
	
	temp.values = L;
	temp.cent_id = 1;
	C.push_back(temp);

	L[0] = 6;
	L[1] = 7;
	
	temp.values = L;
	temp.cent_id = 2;
	C.push_back(temp);
	//done intialization
	*/
	//initialize centroid ids
	vector<int> ids(K);
	for(i =0;i<K;i++)
		ids[i]=i;
	iter = 0;
	is_change = 1;

//	thrust::device_vector<Centroid> d_C = C;
	double *h_C_x = new double[K];
	double *h_C_y = new double[K];
	cudaMalloc((void**)&d_C_x, K*sizeof(double));
	cudaMalloc((void**)&d_C_y, K*sizeof(double));

	clock_t begin_time = clock();
	while( (iter++ < max_iterations) && is_change)
	{
		cout<<"iteration  = "<<iter<<endl;
		cudaMemcpy(d_C_x, h_C_x, K*sizeof(double), cudaMemcpyHostToDevice);
		cudaMemcpy(d_C_y, h_C_y, K*sizeof(double), cudaMemcpyHostToDevice);

		//CUDA - copy centroid data to device
		prune(root, C,ids);	
//		print_centroid_details(C);
		is_change = update_centroid(C);
//		cout<<is_change<<endl;
		cout<<"after\n";
	}

		print_centroid_details(C);
	std::cout << "time to make tree "<< float( clock () - begin_time ) /  CLOCKS_PER_SEC << endl;
}