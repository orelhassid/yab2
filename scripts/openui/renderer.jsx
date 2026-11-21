import React from 'react';
import { createRoot } from 'react-dom/client';
import { BuiltinActionType, Renderer } from '@openuidev/react-lang';
import { ThemeProvider } from '@openuidev/react-ui';
import { library } from './library.mjs';
import '@openuidev/react-ui/styles/index.css';
import './theme.css';

function post(value) {
    window.webkit?.messageHandlers?.openUIReply?.postMessage(value);
}

const mount = document.getElementById('reply');
let gesture = false;
for (const event of ['click', 'submit', 'keydown']) {
    document.addEventListener(event, e => {
        if (!e.isTrusted) return;
        gesture = true;
        setTimeout(() => { gesture = false; }, 0);
    }, true);
}

function continueChat(event) {
    if (!gesture || event.type !== BuiltinActionType.ContinueConversation) return;
    const values = event.formState;
    const text = values && Object.keys(values).length > 0
        ? `${event.humanFriendlyMessage}\n\nForm values: ${JSON.stringify(values)}`
        : event.humanFriendlyMessage;
    if (typeof text === 'string' && text.length <= 12000) post({ action: text });
}

const renderer = createRoot(mount);
window.showOpenUIReply = reply => {
    const { theme } = reply;
    document.documentElement.style.colorScheme = theme.dark ? 'dark' : 'light';
    for (const color of ['surface', 'border', 'text', 'muted', 'accent']) {
        document.documentElement.style.setProperty(`--yab-${color}`, theme[color]);
    }
    renderer.render(<ThemeProvider mode={theme.dark ? 'dark' : 'light'}>
        <Renderer library={library} response={reply.program} isStreaming={reply.streaming}
            onAction={reply.streaming || reply.submitted ? undefined : continueChat}
            onParseResult={result => {
                if (!reply.streaming && result && !result.root) post({ invalid: true });
            }} />
        {reply.submitted && <p className="sent" role="status">Submitted</p>}
    </ThemeProvider>);
};

new ResizeObserver(() => {
    post({ height: Math.ceil(mount.getBoundingClientRect().height) });
}).observe(mount);
