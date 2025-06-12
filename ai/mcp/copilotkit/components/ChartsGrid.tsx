"use client"
import GenericChart, { ChartProps } from "./GenericChart";
import { useState } from "react";
import { useCopilotAction, useCopilotReadable } from "@copilotkit/react-core";

function DynamicGrid({ charts }: { charts: ChartProps[] }) {
    return (
        charts.map((chart, index) => (
            <div className="flex flex-col gap-4" key={index}>
                <p className="text-white whitespace-nowrap overflow-hidden text-overflow-ellipsis text-(length:--typography-font-sizes-1,20px) leading-[150%] font-bold font-inter">{chart.title}</p>
                <GenericChart {...chart} />
            </div>))
    )
}

export default function ChartsGrid() {
    const [charts, setCharts] = useState<ChartProps[]>([]);

    useCopilotReadable({
        description: "These are all the charts props",
        value: charts,
    });

    useCopilotAction({
        name: "generateChart",
        description: "Generate a chart based on the provided data. Make sure to provide the data in the correct format and specify what field should be used a x-axis.",
        parameters: [
            {
                name: "data",
                type: "object[]",
                description: "Data to be used for the chart. The data should be an array of objects, where each object represents a data point.",
            },
            {
                name: "chartType",
                type: "string",
                description: "Type of chart to be generated. Let's use bar, line, area, or pie.",
            },
            {
                name: "title",
                type: "string",
                description: "Title of the chart. Can't be more than 30 characters.",
            },
            { name: "xAxis", type: "string", description: "x-axis label" }
        ],

        handler: async ({ data, chartType, title, xAxis }) => {
            const newChart: ChartProps = {
                data,
                chartType,
                title,
                xAxis
            };

            setCharts((charts) => [...charts, newChart]);
        },
        render: "Adding chart...",
    });

    return (
        <div className="grid grid-cols-2 lg:grid-cols-2 gap-8">
            {charts.length > 0 ? <DynamicGrid charts={charts} /> :
                <div className="mt-10 flex items-center justify-center w-full h-[400px] border border-[#414141] bg-[#282828] font-inter font-medium leading-[150%] text-base text-[#B3B6BD] rounded-lg">Your chart will appear here</div>}
        </div>
    )
}
