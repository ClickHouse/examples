import '@mantine/core/styles.css';
import './styles.css';
import { Links, Meta, Outlet, Scripts, ScrollRestoration, isRouteErrorResponse } from 'react-router';
import { ColorSchemeScript, MantineProvider, mantineHtmlProps, Container, Title, Text, Button } from '@mantine/core';
import type { Route } from './+types/root';

export function Layout({ children }: { children: React.ReactNode }) {
  return <html lang="en" {...mantineHtmlProps}><head><meta charSet="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <ColorSchemeScript defaultColorScheme="light" /><Meta /><Links /></head>
    <body><MantineProvider defaultColorScheme="light" theme={{ primaryColor: 'teal', defaultRadius: 'md' }}>{children}</MantineProvider>
    <ScrollRestoration /><Scripts /></body></html>;
}
export default function App() { return <Outlet />; }
export function ErrorBoundary({ error }: Route.ErrorBoundaryProps) {
  const message = isRouteErrorResponse(error) && error.status < 500 ? String(error.data) : 'The garden journal could not be loaded. Check the database connection, then try again.';
  return <Container py="xl"><Title order={1}>Something needs attention</Title><Text my="md">{message}</Text><Button component="a" href="/">Return to the journal</Button></Container>;
}
