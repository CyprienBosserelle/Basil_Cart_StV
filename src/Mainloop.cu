#include "Mainloop.h"



template <class T> void MainLoop(Param &XParam, Forcing<float> XForcing, Model<T>& XModel, Model<T> &XModel_g)
{
	
	Loop<T> XLoop = InitLoop(XParam, XModel);

	//Define some useful variables 
	Initmeanmax(XParam, XLoop, XModel, XModel_g);
	

	while (XLoop.totaltime < XParam.endtime)
	{
		// Bnd stuff here
		updateBnd(XParam, XLoop, XForcing, XModel, XModel_g);
		

		// Calculate Forcing at this step


		// Core engine
		if (XParam.GPUDEVICE >= 0)
		{
			FlowGPU(XParam, XLoop, XModel_g);
		}
		else
		{
			FlowCPU(XParam, XLoop, XModel);
		}
		
		
		// Time keeping
		XLoop.totaltime = XLoop.totaltime + XLoop.dt;

		// Do Sum & Max variables Here
		Calcmeanmax(XParam, XLoop, XModel, XModel_g);

		// Check & collect TSoutput
		pointoutputstep(XParam, XLoop, XModel, XModel_g);

		// Check for map output
		mapoutput(XParam, XLoop, XModel, XModel_g);

		// Reset mean/Max if needed
		
	}
	

	

}
template void MainLoop<float>(Param& XParam, Forcing<float> XForcing, Model<float>& XModel, Model<float>& XModel_g);
template void MainLoop<double>(Param& XParam, Forcing<float> XForcing, Model<double>& XModel, Model<double>& XModel_g);




 
template <class T> Loop<T> InitLoop(Param &XParam, Model<T> &XModel)
{
	Loop<T> XLoop;
	XLoop.atmpuni = XParam.Paref;
	XLoop.totaltime = XParam.totaltime;
	XLoop.nextoutputtime = XParam.totaltime + XParam.outputtimestep;
	
	// Prepare output files
	InitSave2Netcdf(XParam, XModel);
	InitTSOutput(XParam);
	// Add empty row for each output point
	// This will allow for the loop to each point to work later
	for (int o = 0; o < XParam.TSnodesout.size(); o++)
	{
		XLoop.TSAllout.push_back(std::vector<Pointout>());
	}

	// GPU stuff
	if (XParam.GPUDEVICE >= 0)
	{
		XLoop.blockDim = (16, 16, 1);
		XLoop.gridDim = (XParam.nblk, 1, 1);
	}

	XLoop.hugenegval = std::numeric_limits<T>::min();

	XLoop.hugeposval = std::numeric_limits<T>::max();
	XLoop.epsilon = std::numeric_limits<T>::epsilon();

	return XLoop;

}

template <class T> void updateBnd(Param XParam, Loop<T> XLoop, Forcing<float> XForcing, Model<T> XModel, Model<T> XModel_g)
{
	if (XParam.GPUDEVICE >= 0)
	{
		Flowbnd(XParam, XLoop, XModel_g.blocks, XForcing.left, XModel_g.evolv);
		Flowbnd(XParam, XLoop, XModel_g.blocks, XForcing.right, XModel_g.evolv);
		Flowbnd(XParam, XLoop, XModel_g.blocks, XForcing.top, XModel_g.evolv);
		Flowbnd(XParam, XLoop, XModel_g.blocks, XForcing.bot, XModel_g.evolv);
	}
	else
	{
		Flowbnd(XParam, XLoop, XModel.blocks, XForcing.left, XModel.evolv);
		Flowbnd(XParam, XLoop, XModel.blocks, XForcing.right, XModel.evolv);
		Flowbnd(XParam, XLoop, XModel.blocks, XForcing.top, XModel.evolv);
		Flowbnd(XParam, XLoop, XModel.blocks, XForcing.bot, XModel.evolv);
	}
}



template <class T> void resetmaxGPU(Param XParam, Loop<T> XLoop, BlockP<T> XBlock, EvolvingP<T>& XEv)
{
	dim3 blockDim = (XParam.blkwidth, XParam.blkwidth, 1);
	dim3 gridDim = (XParam.nblk, 1, 1);

	reset_var <<< gridDim, blockDim, 0 >>> (XParam.halowidth, XBlock.active, XLoop.hugenegval, XEv.h);
	reset_var <<< gridDim, blockDim, 0 >>> (XParam.halowidth, XBlock.active, XLoop.hugenegval, XEv.zs);
	reset_var <<< gridDim, blockDim, 0 >>> (XParam.halowidth, XBlock.active, XLoop.hugenegval, XEv.u);
	reset_var <<< gridDim, blockDim, 0 >>> (XParam.halowidth, XBlock.active, XLoop.hugenegval, XEv.v);
	CUDA_CHECK(cudaDeviceSynchronize());
	
}


template <class T> void resetmaxCPU(Param XParam, Loop<T> XLoop, BlockP<T> XBlock, EvolvingP<T>& XEv)
{
	
	InitArrayBUQ(XParam, XBlock, XLoop.hugenegval, XEv.h);
	InitArrayBUQ(XParam, XBlock, XLoop.hugenegval, XEv.zs);
	InitArrayBUQ(XParam, XBlock, XLoop.hugenegval, XEv.u);
	InitArrayBUQ(XParam, XBlock, XLoop.hugenegval, XEv.v);
	
}


template <class T> void resetmeanCPU(Param XParam, Loop<T> XLoop, BlockP<T> XBlock, EvolvingP<T> & XEv)
{
	
	InitArrayBUQ(XParam, XBlock, T(0.0), XEv.h);
	InitArrayBUQ(XParam, XBlock, T(0.0), XEv.zs);
	InitArrayBUQ(XParam, XBlock, T(0.0), XEv.u);
	InitArrayBUQ(XParam, XBlock, T(0.0), XEv.v);
}
template void resetmeanCPU<float>(Param XParam, Loop<float> XLoop, BlockP<float> XBlock, EvolvingP<float>& XEv);
template void resetmeanCPU<double>(Param XParam, Loop<double> XLoop, BlockP<double> XBlock, EvolvingP<double>& XEv);

template <class T> void resetmeanGPU(Param XParam, Loop<T> XLoop, BlockP<T> XBlock, EvolvingP<T>& XEv)
{
	dim3 blockDim = (XParam.blkwidth, XParam.blkwidth, 1);
	dim3 gridDim = (XParam.nblk, 1, 1);
	//
	reset_var <<< gridDim, blockDim, 0 >>> (XParam.halowidth, XBlock.active, T(0.0), XEv.h);
	reset_var <<< gridDim, blockDim, 0 >>> (XParam.halowidth, XBlock.active, T(0.0), XEv.zs);
	reset_var <<< gridDim, blockDim, 0 >>> (XParam.halowidth, XBlock.active, T(0.0), XEv.u);
	reset_var <<< gridDim, blockDim, 0 >>> (XParam.halowidth, XBlock.active, T(0.0), XEv.v);
	CUDA_CHECK(cudaDeviceSynchronize());
	

}
template void resetmeanGPU<float>(Param XParam, Loop<float> XLoop, BlockP<float> XBlock, EvolvingP<float>& XEv);
template void resetmeanGPU<double>(Param XParam, Loop<double> XLoop, BlockP<double> XBlock, EvolvingP<double>& XEv);




template <class T> void Calcmeanmax(Param XParam, Loop<T> &XLoop, Model<T> XModel, Model<T> XModel_g)
{
	dim3 blockDim = (XParam.blkwidth, XParam.blkwidth, 1);
	dim3 gridDim = (XParam.nblk, 1, 1);

	if (XParam.outmean)
	{
		if (XParam.GPUDEVICE >= 0)
		{
			addavg_varGPU <<< gridDim, blockDim, 0 >>> (XParam, XModel_g.blocks, XModel_g.evmean.h, XModel_g.evolv.h);
			addavg_varGPU <<< gridDim, blockDim, 0 >>> (XParam, XModel_g.blocks, XModel_g.evmean.zs, XModel_g.evolv.zs);
			addavg_varGPU <<< gridDim, blockDim, 0 >>> (XParam, XModel_g.blocks, XModel_g.evmean.u, XModel_g.evolv.u);
			addavg_varGPU <<< gridDim, blockDim, 0 >>> (XParam, XModel_g.blocks, XModel_g.evmean.v, XModel_g.evolv.v);
			CUDA_CHECK(cudaDeviceSynchronize());
		}
		else
		{
			addavg_varCPU(XParam, XModel.blocks, XModel.evmean.h, XModel.evolv.h);
			addavg_varCPU(XParam, XModel.blocks, XModel.evmean.zs, XModel.evolv.zs);
			addavg_varCPU(XParam, XModel.blocks, XModel.evmean.u, XModel.evolv.u);
			addavg_varCPU(XParam, XModel.blocks, XModel.evmean.v, XModel.evolv.v);
		}

		XLoop.nstep++;

		if (XLoop.nextoutputtime - XLoop.totaltime <= XLoop.dt * T(0.00001))
		{
			// devide by number of steps
			if (XParam.GPUDEVICE >= 0)
			{
				divavg_varGPU <<< gridDim, blockDim, 0 >>> (XParam, XModel_g.blocks, T(XLoop.nstep), XModel_g.evmean.h);
				divavg_varGPU <<< gridDim, blockDim, 0 >>> (XParam, XModel_g.blocks, T(XLoop.nstep), XModel_g.evmean.zs);
				divavg_varGPU <<< gridDim, blockDim, 0 >>> (XParam, XModel_g.blocks, T(XLoop.nstep), XModel_g.evmean.u);
				divavg_varGPU <<< gridDim, blockDim, 0 >>> (XParam, XModel_g.blocks, T(XLoop.nstep), XModel_g.evmean.v);
				CUDA_CHECK(cudaDeviceSynchronize());
			}
			else
			{
				divavg_varCPU(XParam, XModel.blocks, T(XLoop.nstep), XModel.evmean.h);
				divavg_varCPU(XParam, XModel.blocks, T(XLoop.nstep), XModel.evmean.zs);
				divavg_varCPU(XParam, XModel.blocks, T(XLoop.nstep), XModel.evmean.u);
				divavg_varCPU(XParam, XModel.blocks, T(XLoop.nstep), XModel.evmean.v);
			}

			//XLoop.nstep will be reset after a save to the disk which occurs in a different function
		}

	}
	if (XParam.outmax)
	{
		if (XParam.GPUDEVICE >= 0)
		{
			max_varGPU <<< gridDim, blockDim, 0 >>> (XParam, XModel_g.blocks, XModel_g.evmax.h, XModel_g.evolv.h);
			max_varGPU <<< gridDim, blockDim, 0 >>> (XParam, XModel_g.blocks, XModel_g.evmax.zs, XModel_g.evolv.zs);
			max_varGPU <<< gridDim, blockDim, 0 >>> (XParam, XModel_g.blocks, XModel_g.evmax.u, XModel_g.evolv.u);
			max_varGPU <<< gridDim, blockDim, 0 >>> (XParam, XModel_g.blocks, XModel_g.evmax.v, XModel_g.evolv.v);
		}
		else
		{
			max_varCPU(XParam, XModel.blocks, XModel.evmax.h, XModel.evolv.h);
			max_varCPU(XParam, XModel.blocks, XModel.evmax.zs, XModel.evolv.zs);
			max_varCPU(XParam, XModel.blocks, XModel.evmax.u, XModel.evolv.u);
			max_varCPU(XParam, XModel.blocks, XModel.evmax.v, XModel.evolv.v);
		}
	}
}


template <class T> void resetmeanmax(Param XParam, Loop<T> &XLoop, Model<T> XModel, Model<T> XModel_g)
{
	// Reset mean and or max only at output steps
	if (XLoop.nextoutputtime - XLoop.totaltime <= XLoop.dt * T(0.00001))
	{
		//Define some useful variables 
		if (XParam.outmean)
		{
			if (XParam.GPUDEVICE >= 0)
			{
				resetmeanGPU(XParam, XLoop, XModel_g.blocks, XModel_g.evmean);
			}
			else
			{
				resetmeanCPU(XParam, XLoop, XModel.blocks, XModel.evmean);
			}
			XLoop.nstep = 0;
		}

		//Reset Max 
		if (XParam.outmax && XParam.resetmax)
		{
			if (XParam.GPUDEVICE >= 0)
			{
				resetmaxGPU(XParam, XLoop, XModel_g.blocks, XModel_g.evmax);
			}
			else
			{
				resetmaxCPU(XParam, XLoop, XModel.blocks, XModel.evmax);

			}
		}
	}
}

template <class T> void Initmeanmax(Param XParam, Loop<T> XLoop, Model<T> XModel, Model<T> XModel_g)
{
	//at the initiial step overide the reset max to initialise the max variable (if needed)
	//this override is not preserved so wont affect the rest of the loop
	XParam.resetmax = true;
	XLoop.nextoutputtime = XLoop.totaltime;
	XLoop.dt = T(1.0);
	resetmeanmax(XParam, XLoop, XModel, XModel_g);
}


template <class T> void mapoutput(Param XParam, Loop<T> XLoop,Model<T> XModel, Model<T> XModel_g)
{
	if (XLoop.nextoutputtime - XLoop.totaltime <= XLoop.dt * T(0.00001) && XParam.outputtimestep > 0.0)
	{
		if (XParam.GPUDEVICE >= 0)
		{
			for (int ivar = 0; ivar < XParam.outvars.size(); ivar++)
			{
				CUDA_CHECK(cudaMemcpy(XModel.OutputVarMap[XParam.outvars[ivar]], XModel_g.OutputVarMap[XParam.outvars[ivar]], XParam.nblkmem * XParam.blksize * sizeof(T), cudaMemcpyDeviceToHost));
			}
		}

		Save2Netcdf(XParam, XModel);


		XLoop.nextoutputtime = min(XLoop.nextoutputtime + XParam.outputtimestep, XParam.endtime);
	}
}

template <class T> void pointoutputstep(Param XParam, Loop<T> &XLoop, Model<T> XModel, Model<T> XModel_g)
{
	//
	dim3 blockDim = (XParam.blkwidth, XParam.blkwidth, 1);
	dim3 gridDim = (XModel.bndblk.nblkTs, 1, 1);
	FILE* fsSLTS;
	if (XParam.GPUDEVICE>=0)
	{

		for (int o = 0; o < XParam.TSnodesout.size(); o++)
		{
			//
			Pointout stepread;
		
			stepread.time = XParam.totaltime;
			stepread.zs = 0.0;// That is a bit useless
			stepread.h = 0.0;
			stepread.u = 0.0;
			stepread.v = 0.0;
			XLoop.TSAllout[o].push_back(stepread);
					
			
			storeTSout << <gridDim, blockDim, 0 >> > (XParam,(int)XParam.TSnodesout.size(), o, XLoop.nTSsteps, XParam.TSnodesout[o].block, XParam.TSnodesout[o].i, XParam.TSnodesout[o].j, XModel.bndblk.Tsout, XModel_g.evolv, XModel_g.TSstore);
		}
		CUDA_CHECK(cudaDeviceSynchronize());
	}
	else
	{
		for (int o = 0; o < XParam.TSnodesout.size(); o++)
		{
			//
			Pointout stepread;

			int i = memloc(XParam.halowidth, XParam.blkmemwidth, XParam.TSnodesout[o].i, XParam.TSnodesout[o].j, XParam.TSnodesout[o].block);

			stepread.time = XParam.totaltime;
			stepread.zs = XModel.evolv.zs[i];
			stepread.h = XModel.evolv.h[i];;
			stepread.u = XModel.evolv.u[i];;
			stepread.v = XModel.evolv.v[i];;
			XLoop.TSAllout[o].push_back(stepread);

		}
	}
	XLoop.nTSsteps++;

	// if the buffer is full or if the model is complete
	if ((XLoop.nTSsteps + 1) * XParam.TSnodesout.size() * 4 > XParam.maxTSstorage || XParam.endtime - XLoop.totaltime <= XLoop.dt * 0.00001f)
	{

		//Flush to disk
		if (XParam.GPUDEVICE >= 0)
		{
			CUDA_CHECK(cudaMemcpy(XModel.TSstore, XModel_g.TSstore, XParam.maxTSstorage * sizeof(T), cudaMemcpyDeviceToHost));
			int oo;
			
			for (int o = 0; o < XParam.TSnodesout.size(); o++)
			{
				for (int istep = 0; istep < XLoop.TSAllout[o].size(); istep++)
				{
					oo = o * 4 + istep * XParam.TSnodesout.size() * 4;
					//
					XLoop.TSAllout[o][istep].h = XModel.TSstore[0 + oo];
					XLoop.TSAllout[o][istep].zs = XModel.TSstore[1 + oo];
					XLoop.TSAllout[o][istep].u = XModel.TSstore[2 + oo];
					XLoop.TSAllout[o][istep].v = XModel.TSstore[3 + oo];
				}
			}

		}
		for (int o = 0; o < XParam.TSnodesout.size(); o++)
		{
			fsSLTS = fopen(XParam.TSnodesout[o].outname.c_str(), "a");


			for (int n = 0; n < XLoop.nTSsteps; n++)
			{
				//


				fprintf(fsSLTS, "%f\t%.4f\t%.4f\t%.4f\t%.4f\n", XLoop.TSAllout[o][n].time, XLoop.TSAllout[o][n].zs, XLoop.TSAllout[o][n].h, XLoop.TSAllout[o][n].u, XLoop.TSAllout[o][n].v);


			}
			fclose(fsSLTS);
			//reset output buffer
			XLoop.TSAllout[o].clear();
		}
		// Reset buffer counter
		XLoop.nTSsteps = 0;




	}
}


template <class T> __global__ void storeTSout(Param XParam,int noutnodes, int outnode, int istep,int blknode, int inode,int jnode, int * blkTS, EvolvingP<T> XEv, T* store)
{
	unsigned int halowidth = XParam.halowidth;
	unsigned int blkmemwidth = blockDim.y + halowidth * 2;
	unsigned int blksize = blkmemwidth * blkmemwidth;
	unsigned int ix = threadIdx.x;
	unsigned int iy = threadIdx.y;
	unsigned int ibl = blockIdx.x;
	unsigned int ib = blkTS[ibl];

	int i = memloc(halowidth, blkmemwidth, ix, iy, ib);


	if (ib == blknode && ix == inode && iy == jnode)
	{
		store[0 + outnode * 4 + istep * noutnodes * 4] = XEv.h[i];
		store[1 + outnode * 4 + istep * noutnodes * 4] = XEv.zs[i];
		store[2 + outnode * 4 + istep * noutnodes * 4] = XEv.u[i];
		store[3 + outnode * 4 + istep * noutnodes * 4] = XEv.v[i];
	}
}

template <class T> __global__ void addavg_varGPU(Param XParam,BlockP<T> XBlock, T* Varmean, T* Var)
{
	unsigned int halowidth = XParam.halowidth;
	unsigned int blkmemwidth = blockDim.y + halowidth * 2;
	
	unsigned int ix = threadIdx.x;
	unsigned int iy = threadIdx.y;
	unsigned int ibl = blockIdx.x;
	unsigned int ib = XBlock.active[ibl];

	int i = memloc(halowidth, blkmemwidth, ix, iy, ib);


	Varmean[i] = Varmean[i] + Var[i];
	
}

template <class T> __host__ void addavg_varCPU(Param XParam, BlockP<T> XBlock, T* Varmean, T* Var)
{
	int ib, n;
	for (int ibl = 0; ibl < XParam.nblk; ibl++)
	{
		ib = XBlock.active[ibl];

		for (int iy = 0; iy < XParam.blkwidth; iy++)
		{
			for (int ix = 0; ix < XParam.blkwidth; ix++)
			{
				int i = memloc(XParam.halowidth, XParam.blkmemwidth, ix, iy, ib);

				Varmean[i] = Varmean[i] + Var[i];
			}
		}
	}

}

template <class T> __global__ void divavg_varGPU(Param XParam, BlockP<T> XBlock, T ntdiv, T* Varmean)
{
	unsigned int halowidth = XParam.halowidth;
	unsigned int blkmemwidth = blockDim.y + halowidth * 2;
	
	unsigned int ix = threadIdx.x;
	unsigned int iy = threadIdx.y;
	unsigned int ibl = blockIdx.x;
	unsigned int ib = XBlock.active[ibl];

	int i = memloc(halowidth, blkmemwidth, ix, iy, ib);
	
	Varmean[i] = Varmean[i] / ntdiv;

}

template <class T> __host__ void divavg_varCPU(Param XParam, BlockP<T> XBlock, T ntdiv, T* Varmean)
{
	int ib, n;
	for (int ibl = 0; ibl < XParam.nblk; ibl++)
	{
		ib = XBlock.active[ibl];

		for (int iy = 0; iy < XParam.blkwidth; iy++)
		{
			for (int ix = 0; ix < XParam.blkwidth; ix++)
			{
				int i = memloc(XParam.halowidth, XParam.blkmemwidth, ix, iy, ib);

				Varmean[i] = Varmean[i] / ntdiv;
			}
		}
	}

}

template <class T> __global__ void max_varGPU(Param XParam, BlockP<T> XBlock, T* Varmax, T* Var)
{
	unsigned int halowidth = XParam.halowidth;
	unsigned int blkmemwidth = blockDim.y + halowidth * 2;
	
	unsigned int ix = threadIdx.x;
	unsigned int iy = threadIdx.y;
	unsigned int ibl = blockIdx.x;
	unsigned int ib = XBlock.active[ibl];

	int i = memloc(halowidth, blkmemwidth, ix, iy, ib);

	Varmax[i] = max(Varmax[i], Var[i]);

}

template <class T> __host__ void max_varCPU(Param XParam, BlockP<T> XBlock, T* Varmax, T* Var)
{
	int ib, n;
	for (int ibl = 0; ibl < XParam.nblk; ibl++)
	{
		ib = XBlock.active[ibl];

		for (int iy = 0; iy < XParam.blkwidth; iy++)
		{
			for (int ix = 0; ix < XParam.blkwidth; ix++)
			{
				int i = memloc(XParam.halowidth, XParam.blkmemwidth, ix, iy, ib);

				Varmax[i] = utils::max(Varmax[i], Var[i]);
			}
		}
	}

}

