import './Embedded.css';
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import AceEditor from "react-ace-builds";
import "react-ace-builds/webpack-resolver-min";

import { PhpWeb } from 'php-wasm/PhpWeb';
import { createRoot } from 'react-dom/client';
import Confirm from './Confirm';

const sharedLibs = [
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-zlib@0.0.9-d'),
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-libzip@0.0.9-c'),
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-iconv@0.0.9-f'),
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-libicu@0.0.9-r'),
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-sqlite@0.0.9-s'),
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-freetype@0.0.9-c'),
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-libpng@0.0.9-h'),
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-libjpeg@0.0.9-c'),
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-libxml@0.0.9-h'),
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-gd@0.0.9-c'),
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-openssl@0.0.9-e'),
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-phar@0.0.9-b'),
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-tidy@0.0.9-d'),
	// await import('https://cdn.jsdelivr.net/npm/php-wasm-yaml@0.0.9-f'),
];

// const sharedLibs = [
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-zlib'),
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-libzip'),
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-iconv'),
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-libicu'),
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-sqlite@0.0.9-t'),
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-freetype'),
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-libpng'),
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-libjpeg'),
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-libxml'),
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-gd'),
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-openssl'),
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-phar'),
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-tidy'),
// 	await import('https://cdn.jsdelivr.net/npm/php-wasm-yaml'),
// ];

const files = [{ parent: '/preload/', name: 'icudt72l.dat', url: '/icudt72l.dat' }];

const ini = `
	date.timezone=${Intl.DateTimeFormat().resolvedOptions().timeZone}
	expose_php=0
`;

let init = false;

function Embedded() {
	const phpRef = useRef(null);
	const inputBox = useRef(null);
	const selectDemoBox = useRef(null);
	const htmlRadio = useRef(null);
	const textRadio = useRef(null);
	const editor = useRef(null);
	const input = useRef('');

	const persist = useRef('');
	const single  = useRef('');

	const [exitCode, setExitCode] = useState('');
	const [stdOut, setStdOut] = useState('');
	const [stdErr, setStdErr] = useState('');
	const [stdRet, setStdRet] = useState('');
	const [overlay, setOverlay] = useState(null);

	const [running, setRunning] = useState(false);
	const [displayMode, setDisplayMode] = useState('');
	const [outputMode, setOutputMode] = useState('');
	const [statusMessage, setStatusMessage] = useState('php-wasm');

	const onOutput = event => setStdOut(stdOut => String(stdOut || '') + event.detail.join(''));
	const onError  = event => setStdErr(stdErr => String(stdErr || '') + event.detail.join(''));

	const refreshPhp = useCallback(() => {
		// phpRef.current = new PhpWeb({persist: [{mountPath:'/persist'}, {mountPath:'/config'}]});
		// phpRef.current = new PhpWeb({sharedLibs, ini, locateFile: filename => {
		// 	console.log(filename);
		// }});
		phpRef.current = new PhpWeb({sharedLibs, files, ini});

		const php = phpRef.current;

		php.addEventListener('output', onOutput);
		php.addEventListener('error', onError);

		return () => {
			php.removeEventListener('output', onOutput);
			php.removeEventListener('error', onError);
		};
	}, []);

	useEffect(() => {
		if(!init)
		{
			refreshPhp();
			init = true;
		}
	}, [refreshPhp]);

	const query = useMemo(() => new URLSearchParams(window.location.search), []);

	const singleChanged = () => setOutputMode(single.current.checked ? 'single' : 'normal');
	const formatSelected = event => setDisplayMode(event.target.value);

	const codeChanged = newValue => input.current = newValue;

	const runCode = useCallback(() => {
		setRunning(true);

		setStatusMessage('Executing...');

		if(!persist.current.checked)
		{
			setStdOut('');
			setStdErr('');
		}

		setStdRet('');

		const phpCode = editor.current.editor.getValue();

		query.set('code', encodeURIComponent(phpCode));

		window.history.replaceState({}, document.title, "?" + query.toString());

		let code = input.current;

		setTimeout(async () => {
			if(single.current.checked)
			{
				code = code.replace(/^\s*<\?php/, '');
				code = code.replace(/\?>\s*/, '');

				try
				{
					const ret = await phpRef.current.exec(code);
					setStdRet(ret);
					persist.current.checked || phpRef.current.refresh();
				}
				catch(error)
				{
					console.error(error);
				}
				finally
				{
					setTimeout(() => {
						setStatusMessage('php-wasm ready!')
						setRunning(false);
					}, 1);
				}
			}
			else
			{
				try
				{
					const exitCode = await phpRef.current.run(code);
					setExitCode(exitCode);
					persist.current.checked || phpRef.current.refresh();
				}
				catch(error)
				{
					console.error(error)
				}
				finally
				{
					setTimeout(() => {
						setStatusMessage('php-wasm ready!')
						setRunning(false);
					}, 1);
				}
			}
		}, 1);
	}, [query]);

	const loadDemo = useCallback(demoName => {
		if(demoName === 'drupal.php')
		{
			setOverlay(<Confirm
				onConfirm = { () => window.location = process.env.PUBLIC_URL + '/select-framework.html' }
				onCancel = { () => setOverlay(null) }
				message = {(
					<span>The Drupal demo has been moved into the <b>php-cgi-wasm</b> demo. Would you like to go there now?</span>
				)}
			/>);
			return;
		}

		setStdOut('');
		setStdErr('');
		setStdRet('');

		fetch(process.env.PUBLIC_URL + '/scripts/' + demoName)
		.then(response => response.text())
		.then(async phpCode => {
			editor.current.editor.setValue(phpCode, -1);

			refreshPhp();

			selectDemoBox.current.value = demoName;

			await phpRef.current.binary;

			document.querySelector('#example').innerHTML = '';

			const firstLine = String(phpCode.split(/\n/).shift());
			const settings  = JSON.parse(firstLine.split('//').pop()) || {};

			persist.current.checked = settings.persist ?? persist.current.checked;
			single.current.checked = settings['single-expression'] ?? single.current.checked;

			if(settings['render-as'])
			{
				setDisplayMode(settings['render-as']);

				htmlRadio.current.checked = settings['render-as'] === 'html';
				textRadio.current.checked = settings['render-as'] !== 'html';
			}

			setOutputMode(single.current.checked ? 'single' : 'normal');

			if(settings.autorun)
			{
				setStatusMessage('Executing...');
				setTimeout(runCode, 16);
			}

			query.set('persist', persist.current.checked ? 1 : 0);
			query.set('single-expression', single.current.checked ? 1 : 0);

			if(phpCode.length < 1024)
			{
				query.set('code', encodeURIComponent(phpCode));
			}

			window.history.replaceState({}, document.title, "?" + query.toString());
		});
	}, [query, refreshPhp, runCode]);

	useEffect(() => {
		if(inputBox.current)
		{
			return;
		}

		inputBox.current = document.getElementById('input-box');

		const inputRoot = createRoot(inputBox.current);
		const queryCode = query.get('code') || '';

		persist.current.checked = !!query.get('persist');
		single.current.checked  = !!query.get('single-expression');

		const decodedCode = decodeURIComponent(queryCode);

		input.current = decodedCode;
		inputRoot.render(
			<AceEditor
				mode = "php"
				theme = "monokai"
				onChange = {codeChanged}
				name = "input"
				width = "100%"
				height = "100%"
				ref = {editor}
				value = {decodedCode}
			/>
		);
		const firstLine = String(decodedCode.split(/\n/).shift());
		const settings  = {};

		try
		{
			Object.assign(settings, JSON.parse(firstLine.split('//').pop()));
		}
		catch
		{}

		persist.current.checked = settings.persist ?? persist.current.checked;
		single.current.checked = settings['single-expression'] ?? single.current.checked;
		setOutputMode(single.current.checked ? 'single' : 'normal');

		if(settings['render-as'])
		{
			setDisplayMode(settings['render-as']);

			htmlRadio.current.checked = settings['render-as'] === 'html';
			textRadio.current.checked = settings['render-as'] !== 'html';
		}

		if(settings.autorun)
		{
			setTimeout(runCode, 1);
		}

		if(editor.current && query.has('code'))
		{
			editor.current.editor.setValue(query.has('code'), -1);
		}
		else if(query.has('demo'))
		{
			loadDemo(query.get('demo'));
			query.delete('demo');
		}

	}, [query, loadDemo, runCode]);

	const demoSelected = () => loadDemo(selectDemoBox.current.value);

	const onKeyDown = event => {
		if(event.key === 'Enter' && event.ctrlKey)
		{
			runCode();
			return;
		}
	};

	useEffect(() => {

		window.addEventListener('keydown', onKeyDown);
		return () => {
			window.removeEventListener('keydown', onKeyDown);
		}
	}, []);

	const openFile = async event => {
		const file = event.target.files[0];
		editor.current.editor.setValue(await file.text(), -1);;
	};

	return (
		<div className="Embedded" data-display-mode = {displayMode} data-output-mode = {outputMode} data-running = {running ? 1: 0}>
			<div className='bevel margined column'>
				<div className = "row header toolbar">
					<div className = "cols">
						<div className = "row start">
							<a href = { process.env.PUBLIC_URL || "/" }>
								<img src = "sean-icon.png" alt = "sean" />
							</a>
							<h1><a href = { process.env.PUBLIC_URL || "/" }>php-wasm</a></h1>
							<hr />
							<select data-select-demo ref = {selectDemoBox}>
								<option value>Select a Demo</option>
								<option value = "hello-world.php">Hello, World!</option>
								<option value = "callbacks.php">Javascript Callbacks</option>
								<option value = "import.php">Import Javascript Modules</option>
								<option value = "curvature.php">Curvature</option>
								<option value = "phpinfo.php">phpinfo();</option>
								<option value = "fetch.php">Fetch</option>
								<option value = "promise.php">Promise</option>
								<option value = "persistent-memory.php">Persistent Memory</option>
								<option value = "dom-access.php">DOM Access</option>
								<option value = "goto.php">GoTo</option>
								<option value = "stdio.php">StdOut, StdIn, & Return</option>
								<option value = "sqlite.php">SQLite</option>
								<option value = "sqlite-pdo.php">SQLite (PDO)</option>
								<option value = "json.php">JSON</option>
								<option value = "closures.php">Closures</option>
								<option value = "files.php">Files</option>
								<option value = "zend-benchmark.php">Zend Benchmark</option>
								<option value = "drupal.php">Drupal 7</option>
							</select>
							<button data-load-demo onClick = {demoSelected}>load</button>
						</div>
					</div>
					<div className = "separator"></div>
					<div className = "row flex-end">
						<hr />
						<div className = "rows spread">
							<label>
								<span>text</span>
								<input value = "text" type = "radio" name = "render-as" onChange = {formatSelected} ref = {textRadio} />
							</label>
							<label>
								<span>html</span>
								<input value = "html" type = "radio" name = "render-as" onChange = {formatSelected} ref = {htmlRadio} />
							</label>
						</div>
						&nbsp;
						<div className = "rows spread">
							<label>
								<span>Persist Memory</span>
								<input type = "checkbox" id = "persist" ref = { persist } />
							</label>
							<label>
								<span>Single Expression</span>
								<input type = "checkbox" id = "singleExpression" ref = { single } onChange = {singleChanged} />
							</label>
						</div>
						<button data-run onClick = { () => setTimeout(runCode, 16) }><span>run</span></button>
					</div>
				</div>

				<div className = "row body">
					<div className = "panel">
						<div className = "input">
							<div className = "cols">
								<label tabIndex="-1">
									<img src = "php.png" alt = "php" /> <span>PHP Code</span>
								</label>
								<label id = "openFile" className = "collapse"tabIndex="-1">
									open file<input type = "file" accept=".php" onChange = {openFile} />
								</label>
							</div>
							<div className = "liquid" id = "input-box"></div>
						</div>
					</div>

					<div className = "panel">
						<div id = "ret">
							<div className = "cols">
								<label tabIndex="-1">return</label>
							</div>
							<div className = "stdret output liquid">
								<div className = "column">
									<iframe srcDoc = {stdRet} title = "output" sandbox = "allow-same-origin allow-scripts allow-forms" className = "scroller"></iframe>
									<div className = "scroller">{stdRet}</div>
								</div>
							</div>
						</div>
						<div>
							<div className = "cols">
								<label tabIndex="-1">stdout</label>
								<label id = "exit" className = "collapse" tabIndex="-1">exit code: {exitCode}<span></span></label>
							</div>
							<div className = "stdout output liquid">
								<div className = "column">
									<iframe srcDoc = {stdOut} title = "output" sandbox = "allow-same-origin allow-scripts allow-forms" className = "scroller"></iframe>
									<div className = "scroller">{stdOut}</div>
								</div>
							</div>
						</div>
						<div>
							<div className = "cols">
								<label tabIndex="-1">stderr</label>
							</div>
							<div className = "stderr output liquid">
								<div className = "column">
								<iframe srcDoc = {stdErr} title = "output" sandbox = "allow-same-origin allow-scripts allow-forms" className = "scroller"></iframe>
									<div className = "scroller">{stdErr}</div>
								</div>
							</div>
						</div>
					</div>
				</div>

				<div id = "example"></div>

				<div className = "row status toolbar">
					<div>
						<div className = "row start" data-status>
							{statusMessage}
						</div>
					</div>
					<div>
					</div>
				</div>
			</div>
			<div className = "overlay">{overlay}</div>
		</div>
	);
}

export default Embedded;
