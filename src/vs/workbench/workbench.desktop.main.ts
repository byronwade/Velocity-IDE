/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/


// #######################################################################
// ###                                                                 ###
// ### !!! PLEASE ADD COMMON IMPORTS INTO WORKBENCH.COMMON.MAIN.TS !!! ###
// ###                                                                 ###
// #######################################################################

//#region --- workbench common

import './workbench.common.main.js';

//#endregion


//#region --- workbench (desktop main)

import './electron-browser/desktop.main.js';
import './electron-browser/desktop.contribution.js';

//#endregion


//#region --- workbench parts

import './electron-browser/parts/dialogs/dialog.contribution.js';

//#endregion


//#region --- workbench services

import './services/textfile/electron-browser/nativeTextFileService.js';
import './services/dialogs/electron-browser/fileDialogService.js';
import './services/workspaces/electron-browser/workspacesService.js';
import './services/menubar/electron-browser/menubarService.js';
import './services/update/electron-browser/updateService.js';
import './services/url/electron-browser/urlService.js';
import './services/lifecycle/electron-browser/lifecycleService.js';
import './services/title/electron-browser/titleService.js';
import './services/host/electron-browser/nativeHostService.js';
import './services/request/electron-browser/requestService.js';
import './services/clipboard/electron-browser/clipboardService.js';
import './services/contextmenu/electron-browser/contextmenuService.js';
import './services/workspaces/electron-browser/workspaceEditingService.js';
import './services/configurationResolver/electron-browser/configurationResolverService.js';
import './services/accessibility/electron-browser/accessibilityService.js';
import './services/keybinding/electron-browser/nativeKeyboardLayout.js';
import './services/path/electron-browser/pathService.js';
import './services/themes/electron-browser/nativeHostColorSchemeService.js';
import './services/extensionManagement/electron-browser/extensionManagementService.js';
import './services/encryption/electron-browser/encryptionService.js';
import './services/imageResize/electron-browser/imageResizeService.js';
import './services/browserElements/electron-browser/browserElementsService.js';
import './services/secrets/electron-browser/secretStorageService.js';
import './services/localization/electron-browser/languagePackService.js';
import './services/telemetry/electron-browser/telemetryService.js';
import './services/extensions/electron-browser/extensionHostStarter.js';
import '../platform/extensionResourceLoader/common/extensionResourceLoaderService.js';
import './services/localization/electron-browser/localeService.js';
import './services/extensions/electron-browser/extensionsScannerService.js';
import './services/extensionManagement/electron-browser/extensionManagementServerService.js';
import './services/extensionManagement/electron-browser/extensionGalleryManifestService.js';
import './services/extensionManagement/electron-browser/extensionTipsService.js';
import './services/userDataSync/electron-browser/userDataSyncService.js';
import './services/userDataSync/electron-browser/userDataAutoSyncService.js';
import './services/timer/electron-browser/timerService.js';
import './services/environment/electron-browser/shellEnvironmentService.js';
import './services/integrity/electron-browser/integrityService.js';
import './services/workingCopy/electron-browser/workingCopyBackupService.js';
import './services/checksum/electron-browser/checksumService.js';
import '../platform/remote/electron-browser/sharedProcessTunnelService.js';
import './services/tunnel/electron-browser/tunnelService.js';
import '../platform/diagnostics/electron-browser/diagnosticsService.js';
import '../platform/profiling/electron-browser/profilingService.js';
import '../platform/telemetry/electron-browser/customEndpointTelemetryService.js';
import '../platform/remoteTunnel/electron-browser/remoteTunnelService.js';
import './services/files/electron-browser/elevatedFileService.js';
import './services/search/electron-browser/searchService.js';
import './services/workingCopy/electron-browser/workingCopyHistoryService.js';
import './services/userDataSync/browser/userDataSyncEnablementService.js';
import './services/extensions/electron-browser/nativeExtensionService.js';
import '../platform/userDataProfile/electron-browser/userDataProfileStorageService.js';
import './services/auxiliaryWindow/electron-browser/auxiliaryWindowService.js';
import '../platform/extensionManagement/electron-browser/extensionsProfileScannerService.js';
import '../platform/webContentExtractor/electron-browser/webContentExtractorService.js';
import './services/process/electron-browser/processService.js';

// MCP services — register only when feature enabled (lazy import below for contrib;
// service modules stay for DI compatibility with Null implementations when unused)
import './services/mcp/electron-browser/mcpGalleryManifestService.js';
import './services/mcp/electron-browser/mcpWorkbenchManagementService.js';

import { registerSingleton } from '../platform/instantiation/common/extensions.js';
import { IUserDataInitializationService, UserDataInitializationService } from './services/userData/browser/userDataInit.js';
import { SyncDescriptor } from '../platform/instantiation/common/descriptors.js';
import { getPerformanceForkMode, isPerformanceForkFeatureEnabled } from '../platform/performanceFork/common/performanceForkFeatures.js';

registerSingleton(IUserDataInitializationService, new SyncDescriptor(UserDataInitializationService, [[]], true));


//#endregion


//#region --- workbench contributions (performance-fork gated)

// Core desktop contributions — always
import './contrib/logs/electron-browser/logs.contribution.js';
import './contrib/localization/electron-browser/localization.contribution.js';
import './contrib/files/electron-browser/fileActions.contribution.js';
import './contrib/codeEditor/electron-browser/codeEditor.contribution.js';
import './contrib/extensions/electron-browser/extensions.contribution.js';
import './contrib/terminal/electron-browser/terminal.contribution.js';
import './contrib/themes/browser/themes.test.contribution.js';
import './services/themes/electron-browser/themes.contribution.js';
import './contrib/performance/electron-browser/performance.contribution.js';
import './contrib/externalTerminal/electron-browser/externalTerminal.contribution.js';
import './contrib/webview/electron-browser/webview.contribution.js';
import './contrib/splash/electron-browser/splash.contribution.js';
import './contrib/mergeEditor/electron-browser/mergeEditor.contribution.js';
import './contrib/multiDiffEditor/browser/multiDiffEditor.contribution.js';
import './contrib/encryption/electron-browser/encryption.contribution.js';

const desktopMode = getPerformanceForkMode();

if (isPerformanceForkFeatureEnabled('workbench.debug') || desktopMode !== 'core') {
	await import('./contrib/debug/electron-browser/extensionHostDebugService.js');
}

if (isPerformanceForkFeatureEnabled('workbench.issueReporter')) {
	await import('./contrib/issue/electron-browser/issue.contribution.js');
}

if (isPerformanceForkFeatureEnabled('workbench.processExplorer')) {
	await import('./contrib/processExplorer/electron-browser/processExplorer.contribution.js');
}

if (isPerformanceForkFeatureEnabled('workbench.remote')) {
	await import('./contrib/remote/electron-browser/remote.contribution.js');
}

if (isPerformanceForkFeatureEnabled('workbench.userDataSync')) {
	await import('./contrib/userDataSync/electron-browser/userDataSync.contribution.js');
}

if (isPerformanceForkFeatureEnabled('workbench.tags')) {
	await import('./contrib/tags/electron-browser/workspaceTagsService.js');
	await import('./contrib/tags/electron-browser/tags.contribution.js');
}

if (isPerformanceForkFeatureEnabled('workbench.tasks')) {
	await import('./contrib/tasks/electron-browser/taskService.js');
}

if (isPerformanceForkFeatureEnabled('workbench.localHistory')) {
	await import('./contrib/localHistory/electron-browser/localHistory.contribution.js');
}

if (isPerformanceForkFeatureEnabled('workbench.remoteTunnel')) {
	await import('./contrib/remoteTunnel/electron-browser/remoteTunnel.contribution.js');
}

if (isPerformanceForkFeatureEnabled('workbench.chat')) {
	await import('./contrib/chat/electron-browser/chat.contribution.js');
}

if (isPerformanceForkFeatureEnabled('workbench.inlineChat')) {
	await import('./contrib/inlineChat/electron-browser/inlineChat.contribution.js');
}

if (isPerformanceForkFeatureEnabled('workbench.emergencyAlert')) {
	await import('./contrib/emergencyAlert/electron-browser/emergencyAlert.contribution.js');
}

if (isPerformanceForkFeatureEnabled('workbench.mcp')) {
	await import('./contrib/mcp/electron-browser/mcp.contribution.js');
}

if (isPerformanceForkFeatureEnabled('workbench.policyExport')) {
	await import('./contrib/policyExport/electron-browser/policyExport.contribution.js');
}

//#endregion


export { main } from './electron-browser/desktop.main.js';
