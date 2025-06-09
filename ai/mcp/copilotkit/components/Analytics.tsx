
"use client";
import React, { useEffect } from "react";
import ChartsGrid from "./ChartsGrid";
import { useCopilotChat, useCopilotAction, CatchAllActionRenderProps } from "@copilotkit/react-core";
import { CopilotSidebar } from "@copilotkit/react-ui";
import { DefaultToolRender } from "./DefaultToolRenderer";
import { CopilotKit } from "@copilotkit/react-core";
import { CopilotKitCSSProperties } from "@copilotkit/react-ui";
import "@copilotkit/react-ui/styles.css";
import "./copilotkit.css";

const runtimeUrl = process.env.NEXT_PUBLIC_COPILOTKIT_RUNTIME_URL
const publicApiKey = process.env.NEXT_PUBLIC_COPILOT_API_KEY;

export default function Analytics() {
    return (
        <CopilotKit
            runtimeUrl={runtimeUrl}
            publicApiKey={publicApiKey}
        >
            <main className="p-8" style={
                    {
                    "--copilot-kit-background-color": "#282828",
                    } as CopilotKitCSSProperties
                }>
                <CopilotSidebar
                    Header={SideBarHeader}
                    clickOutsideToClose={true}
                    defaultOpen={true}
                    instructions="You are a helpful assistant that helps the user analyze the UK real estate market. You can help them generate charts, analyze data, and provide insights. For the charts generation, make sure to keep title below 30 characters."
                    labels={{
                        title: "Popup Assistant",
                        initial: "👋 Hi, there! I'm here to help you analyze the UK real estate market."
                    }}
                ><MainContent/></CopilotSidebar>
            </main>
        </CopilotKit>
    )
}

function SideBarHeader() {
    const { reset } = useCopilotChat();
    return (
        <div className="flex justify-between p-4">
            <p className="text-white content-center font-inter font-bold text-lg">Explorer assistant</p>
            <button
                className="px-6 py-3 hover:cursor-pointer text-[#FAFF69]"
                onClick={() => reset()}
            >
                Clear
            </button>
        </div>
    );
}

function MainContent() {
    const { mcpServers, setMcpServers } = useCopilotChat();

    useEffect(() => {
        setMcpServers([
            {
                endpoint: process.env.NEXT_PUBLIC_MCP_ENDPOINT || "http://localhost:8000/sse",
            },
        ]);
    }, []);

    // 🪁 Catch-all Action for rendering MCP tool calls: https://docs.copilotkit.ai/guides/generative-ui?gen-ui-type=Catch+all+renders
    useCopilotAction({
        name: "*",
        render: ({ name, status, args, result }: CatchAllActionRenderProps<[]>) => (
            <DefaultToolRender status={status} name={name} args={args} result={result} />
        ),
    });

    useCopilotAction({
        name: "clearContext",
        description: "Clear the context of the chat.",
        handler: async () => {
            const { reset } = useCopilotChat();
            reset();
        }
    });

    return (
        <div>
            <p className="text-white font-bold font-inter text-2xl leading-6 pb-6">Custom analytics dashboard</p>
            <ChartsGrid/>
        </div>

    )

}
