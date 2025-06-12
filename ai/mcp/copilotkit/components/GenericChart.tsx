import React, { useRef } from 'react';
import ReactECharts from 'echarts-for-react';
import { color } from 'echarts';

export interface DataPoint {
  name: string;
  [key: string]: string | number; // Additional data properties
}

export interface ChartProps {
  data: DataPoint[];
  chartType: 'bar' | 'line' | 'area' | 'pie' | string;
  title: string;
  xAxis?: string; // Optional x-axis label
}

const GenericChart = ({ data, chartType, title, xAxis }: ChartProps) => {

  const colors = [
    '#FAFF69',
    '#FC74FF',
    '#74ACFF',
    '#74FFD5',
    '#FF7C74',
    '#74FF9B',
    '#FFE074',
    '#CF4B4B'
  ];

  const chartRef = useRef(null);
  const xAxisLabel = xAxis || 'name'; // Default x-axis label if not provided
  // Helper function to get keys of data objects, excluding xAxisLabel
  const getDataKeys = () => {
    if (!data || data.length === 0) return [];
    const firstItem = data[0];
    return Object.keys(firstItem).filter(key => key !== xAxisLabel);
  };

  const dataKeys = getDataKeys();
  console.log('Data keys:', dataKeys);
  const categories = data?.map(item => item[xAxisLabel]);

  // Create series array for the chart
  const getSeries = () => {
    if (chartType.toLowerCase() === 'pie') {
      // For pie chart, we need a different structure
      const key = dataKeys[0]; // Using the first data key for pie
      return [{
        type: 'pie',
        radius: '60%',
        data: data.map(item => ({
          name: item[xAxisLabel],
          value: item[key]
        })),
        emphasis: {
          itemStyle: {
          },

          label: {
            show: false
          }

        },
        label: {
          show: false
        },
        color: colors,

      }];
    }

    // For other chart types
    return dataKeys.map(key => ({
      name: key,
      type: chartType.toLowerCase() === 'area' ? 'line' : chartType.toLowerCase(),
      // For area charts, we use line type with areaStyle
      ...(chartType.toLowerCase() === 'area' && { areaStyle: {} }),
      data: data.map(item => item[key])
    }));
  };

  // Generate options for ECharts
  const getOption = () => {
    const baseOption = {
      color: colors,
      // animation: false,
      grid: {
        left: '24px',
        right: '42px',
        // bot/tom: 50,
        containLabel: true
      },

      tooltip: {
        trigger: chartType.toLowerCase() === 'pie' ? 'item' : 'axis',
        ...(chartType.toLowerCase() === 'pie' && {
          formatter: '{a} <br/>{b}: {c} ({d}%)'
        })
      },
      legend: {
        orient: 'horizontal',
        icon: 'circle',
        textStyle: {
          color: '#FFFFFFF',
          fontSize: 16
        },
        bottom: '5%',
      },
      series: getSeries()
      
    };

    // Add additional configuration based on chart type
    if (chartType.toLowerCase() !== 'pie') {
      return {
        ...baseOption,
        grid: {
          left: '3%',
          right: '4%',
          bottom: '15%',
          containLabel: true
        },
        xAxis: {
          type: 'category',
          data: categories,
          boundaryGap: chartType.toLowerCase() !== 'line'
        },
        yAxis: {
          type: 'value'
        }
      };
    }

    return baseOption;
  };

  if (!data || data.length === 0 || dataKeys.length === 0) {
    return (
      <div className="flex items-center justify-center h-64 bg-gray-100 rounded-md">
        <p className="text-lg text-gray-500">No data available</p>
      </div>
    );
  }

  return (
    data? <div
      className='relative rounded-lg h-full justify-between flex flex-col border bg-[#282828] border-[#414141]'>
      <ReactECharts
        ref={chartRef}
        option={getOption()}
        style={{ width: '100%', height: '400px' }}
        className="echarts-for-react"
      />
    </div>: <div
      className='relative rounded-lg bg-slate-850 border border-slate-700 h-full justify-between flex flex-col'>
        <div className="text-red-600 font-semibold text-lg mb-2">Error chart rendering</div>
      </div>
  );
};

export default GenericChart;
