import { build } from 'esbuild';
import { createParser } from '@openuidev/lang-core';
import { copyFile, mkdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { library } from './library.mjs';

const out = resolve(process.argv[2] ?? 'dist');
await mkdir(out, { recursive: true });
await build({
    entryPoints: ['renderer.jsx'],
    outfile: join(out, 'renderer.js'),
    bundle: true,
    minify: true,
    format: 'iife',
    jsx: 'automatic',
    target: 'safari18',
    legalComments: 'linked',
    define: { 'process.env.NODE_ENV': '"production"' },
    loader: { '.woff': 'dataurl', '.woff2': 'dataurl', '.ttf': 'dataurl' },
});

const contract = library.prompt({
    preamble: 'The following OpenUI Lang syntax is available for optional rich content.',
    additionalRules: [
        'Only use the listed built-in components. The root is Card.',
        'Use only @ToAssistant for user-controlled form submissions. Use a concise summary of the requested next step for its label.',
        'Use data already available in the conversation or gathered by the existing tools. Do not invent values.',
        'Do not use Query, Mutation, OpenUrl, images, or external data bindings.',
        'Keep charts compact for the chat column. Use a chart height between 180 and 240 when the component takes a height.',
    ],
});
const examples = [
    [
        'root = Card([header, overview, details])',
        'header = CardHeader("Website summary", "From the mentioned page")',
        'overview = TextContent("The product helps teams organize work.")',
        'details = TextContent("Includes shared views and project reporting.")',
    ],
    [
        'root = Card([header, chart])',
        'header = CardHeader("Monthly totals", "In USD thousands")',
        'chart = BarChart(["Jan", "Feb"], [values], "grouped", null, null, 200)',
        'values = Series("Sales", [42, 55])',
    ],
    [
        'root = Card([header, form])',
        'header = CardHeader("Plan the offsite", "Select a location to draft an agenda")',
        'form = Form("offsite", buttons, [location])',
        'location = FormControl("Location", Select("location", [bangkok, remote], "Choose a location", { required: true }))',
        'bangkok = SelectItem("Bangkok", "Bangkok")',
        'remote = SelectItem("Remote", "Remote")',
        'buttons = Buttons([Button("Draft an agenda", @ToAssistant("Draft an agenda with these details"), "primary")])',
    ],
].map(example => example.join('\n'));
const parser = createParser(library.toJSONSchema());
for (const example of examples) {
    const result = parser.parse(example);
    if (!result.root || result.meta.errors.length > 0) {
        throw new Error(`Invalid OpenUI prompt example: ${JSON.stringify(result.meta.errors)}`);
    }
}
await writeFile(join(out, 'prompt.txt'), [
    'Choose the most useful reply format based on the user’s request. Plain Markdown is the default for quick answers and code help.',
    'If a structured summary, comparison, chart, or a form for collecting details would help, write a brief normal Markdown answer first. Then put exactly one optional OpenUI Lang program in a fenced code block labeled openui. Put the opening and closing fences on their own lines. Never use a program for a simple answer. Keep the Markdown useful on its own.',
    contract,
    'Examples of program bodies:\n' + examples.join('\n\n'),
].join('\n\n'));
await copyFile('index.html', join(out, 'index.html'));
for (const pkg of ['@openuidev/react-ui', '@openuidev/react-lang', '@openuidev/lang-core', 'react', 'react-dom']) {
    await copyFile(join('node_modules', pkg, 'LICENSE'), join(out, pkg.replaceAll('/', '-') + '-LICENSE'));
}
