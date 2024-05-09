import './Common.css';
import './EditorEntry.css';
// import { useEffect, useState } from 'react';
// import { onMessage, sendMessage } from './msg-bus';

import fileIcon from './nomo-dark/file.svg';
import filePhpIcon from './nomo-dark/file.php.svg';
import fileJsIcon from './nomo-dark/file.js.svg';
import fileTxtIcon from './nomo-dark/file.txt.svg';
import fileHtmlIcon from './nomo-dark/file.html.svg';
import fileMdIcon from './nomo-dark/file.markdown.svg';
import fileJsonIcon from './nomo-dark/file.json.svg';
import fileShIcon from './nomo-dark/file.sh.svg';
import fileCssIcon from './nomo-dark/file.css.svg';
import fileXmlIcon from './nomo-dark/file.xml.svg';
import fileYmlIcon from './nomo-dark/file.yaml.svg';
import fileZipIcon from './nomo-dark/file.zip.svg';

import renameIcon from './icons/rename-icon-16.png';
import deleteIcon from './icons/delete-icon-16.png';

import { useEffect, useState } from 'react';
import { onMessage, sendMessage } from './msg-bus';

const icons = {
	php: filePhpIcon
	, module: filePhpIcon
	, inc: filePhpIcon
	, js: fileJsIcon
	, mjs: fileJsIcon
	, txt: fileTxtIcon
	, html: fileHtmlIcon
	, json: fileJsonIcon
	, md: fileMdIcon
	, sh: fileShIcon
	, css: fileCssIcon
	, xml: fileXmlIcon
	, yml: fileYmlIcon
	, yaml: fileYmlIcon
	, zip: fileZipIcon
};

export default function EditorFile({path, name}) {
	const [showContext, setShowContext] = useState(false);
	const [showRename, setShowRename]   = useState(false);
	const [deleted, setDeleted]         = useState(false);
	const [_name, setName] = useState(name);
	const [_path, setPath] = useState(path);

	const onContext = event => {
		event.preventDefault();
		if(!showRename)
		{
			setShowContext(true);
		}
	}

	const onBlur = event => setTimeout(() => setShowContext(false), 160);

	const openFile = () => {
		window.dispatchEvent(new CustomEvent('editor-open-file', {detail: _path}));
	};

	const renameFile = () => {
		setShowRename(true);
	};

	const deleteFile = async () => {
		await sendMessage('unlink', [_path]);
		setShowContext(false);
		setDeleted(true);
	};

	const renameKeyUp = async event => {
		if(event.key === 'Enter')
		{
			const dirPath = _path.substr(0, _path.length - _name.length);

			const newPath = dirPath + event.target.value;

			console.log({_path, newPath});

			await sendMessage('rename', [_path, newPath]);

			setName(event.target.value);
			setPath(newPath);

			setShowRename(false);
		}
		if(event.key === 'Escape')
		{
			setShowRename(false);
		}
	};

	useEffect(() => {
		navigator.serviceWorker.addEventListener('message', onMessage);
		return () => navigator.serviceWorker.removeEventListener('message', onMessage);
	}, []);

	const extension = _path.split('.').pop();

	return !deleted && (
		<div className = "editor-entry editor-file">
			<p onClick = {openFile} tabIndex="0" onContextMenu={onContext}  onBlur = {onBlur}>
				<img className = "file icon" src = {icons[extension] ?? fileIcon} alt = "" />
				{_name}
			</p>
			{showContext && <span className = "contents only-focus">
				<p className = "context" onClick = {() => renameFile(true)}>
					<img className = "file icon" src = {renameIcon} alt = "" />
					Rename
				</p>
				<p className = "context" onClick = {() => deleteFile(true)}>
					<img className = "file icon" src = {deleteIcon} alt = "" />
					Delete
				</p>
			</span>}
			{showRename && <p className = "context">
				<img className = "file icon" src = {fileIcon} alt = "" />
				<input placeholder='filename' onKeyUp = {renameKeyUp} autoFocus={true} defaultValue = {_name} />
			</p>}
		</div>
	);
}
