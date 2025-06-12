"use client";

import * as React from "react";

interface ToolCallProps {
  status: "complete" | "inProgress" | "executing";
  name?: string;
  args?: any;
  result?: any;
}

export function DefaultToolRender({status, name = "", args, result}: ToolCallProps) {
  const [isOpen, setIsOpen] = React.useState(false);

  const classes = {
    container: "bg-[#414141] rounded-lg overflow-hidden w-full shadow-md transition-all duration-200 hover:shadow-xl p-1",
    header: "p-4 flex items-center cursor-pointer group ",
    title: "text-white font-semibold overflow-hidden text-ellipsis",
    statusContainer: "ml-auto flex items-center gap-2",
    statusText: "text-xs text-white font-medium mr-1",
    content: "px-5 pb-5 pt-3 text-white font-mono text-xs bg-[#282828]",
    section: "mb-4",
    sectionTitle: "text-white text-xs uppercase tracking-wider mb-4 mt-4 font-sans font-bold",
    codeBlock: "whitespace-pre-wrap max-h-[200px] overflow-auto text-white p-3 rounded bg-[#414141]",
    chevron: {
      base: "text-white mr-2 transition-transform duration-200",
      open: "rotate-90",
      hover: "group-hover:text-white"
    },
    contentWrapper: {
      base: "overflow-hidden transition-all duration-300 ease-in-out",
      open: "max-h-[600px] opacity-100",
      closed: "max-h-0 opacity-0"
    }
  };

  // Status indicator colors
  const statusColors = {
    complete: "bg-emerald-500 shadow-emerald-500/40",
    inProgress: "bg-amber-500 shadow-amber-500/40",
    executing: "bg-blue-500 shadow-blue-500/40"
  };

  // Simplified format function
  const format = (content: any): React.ReactNode => {
    if (!content) return null;
    return typeof content === "object" 
      ? <span>{JSON.stringify(content, null, 2)}</span>
      : <span>{String(content)}</span>;
  };

  const getStatusColor = () => {
    const baseColor = statusColors[status].split(' ')[0];
    const shadowColor = statusColors[status].split(' ')[1];
    return `${baseColor} ${(status === "inProgress" || status === "executing") ? "animate-pulse" : ""} shadow-[0_0_10px] ${shadowColor}`;
  };

  return (
    <div className={classes.container}>
      <div className={classes.header} onClick={() => setIsOpen(!isOpen)}>
        <ChevronRight isOpen={isOpen} chevronClasses={classes.chevron} />
        <span className={classes.title}>
          {name || "MCP Tool Call"}
        </span>
        <div className={classes.statusContainer}>
          <span className={classes.statusText}>
            {status === "complete" ? "Completed" : status === "inProgress" ? "In Progress" : "Executing"}
          </span>
          <div className={`w-3 h-3 rounded-full ${getStatusColor()}`} />
        </div>
      </div>

      <div className={`${classes.contentWrapper.base} ${isOpen ? classes.contentWrapper.open : classes.contentWrapper.closed}`}>
        <div className={classes.content}>
          <div className={classes.section}>
            <div className={classes.sectionTitle}>Name</div>
            <pre className={classes.codeBlock}>{name}</pre>
          </div>
          {args && (
            <div className={classes.section}>
              <div className={classes.sectionTitle}>Parameters</div>
              <pre className={classes.codeBlock}>{format(args)}</pre>
            </div>
          )}

          {status === "complete" && result && (
            <div className={classes.section}>
              <div className={classes.sectionTitle}>Result</div>
              <pre className={classes.codeBlock}>{format(result)}</pre>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

const ChevronRight = ({ isOpen, chevronClasses }: { isOpen: boolean; chevronClasses: any }) => {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" className={`${chevronClasses.base} ${isOpen ? chevronClasses.open : ''} ${chevronClasses.hover}`} stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="9 18 15 12 9 6"></polyline>
    </svg>
  );
};
