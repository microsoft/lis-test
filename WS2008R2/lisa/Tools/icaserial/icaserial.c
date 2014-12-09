/*
 * Linux on Hyper-V and Azure Test Code, ver. 1.0.0 
 * Copyright (c) Microsoft Corporation 
 *
 * All rights reserved. 
 * Licensed under the Apache License, Version 2.0 (the ""License""); 
 * you may not use this file except in compliance with the License. 
 * You may obtain a copy of the License at 
 *     http://www.apache.org/licenses/LICENSE-2.0 
 * 
 * THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS 
 * OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION 
 * ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR 
 * PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT. 
 * 
 * See the Apache Version 2.0 License for specific language governing 
 * permissions and limitations under the License. 
 */

#ifndef UNICODE
#define UNICODE
#endif

#ifndef _UNICODE
#define _UNICODE
#endif


#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>

//#define ICASERIAL_LOG

#ifdef ICASERIAL_LOG
#define LOG(msg) { wprintf(L"[ICASERIAL LOG] "); wprintf msg; wprintf(L"\n"); }
#define ERR(msg) { wprintf(L"[ICASERIAL ERR] "); wprintf msg; wprintf(L"\n"); }
#else
#define LOG(msg) {}
#define ERR(msg) {}
#endif

#define CHK_COND(cond, dest, msg) { \
	if (!(cond)) { \
		ERR(msg); \
		goto dest; \
	} \
}
#define CHK_LASTERR(cond, _dwRetVal, dest, msg) { \
	if (!(cond)) { \
		ERR(msg); \
		_dwRetVal = GetLastError(); \
		ERR((L"Last Error = %d", _dwRetVal)); \
		goto dest; \
	} \
}

#define PIPE_TIMEOUT 5000
#define BUFSIZE 4096
#define PIPE_READ_STR  L"READ"
#define PIPE_SEND_STR  L"SEND"

typedef enum _PIPE_WORKMODE
{
	PIPE_READMODE  = 0,
	PIPE_SENDMODE = 1
} PIPE_WORKMODE;

typedef enum _PIPE_CONNECTION_STATE
{
	PIPE_BAD_STATE  = 0,
	PIPE_CONNECTING = 1,
	PIPE_READING	= 2,
	PIPE_WRITING	= 3,
	PIPE_COMPLETE   = 4
} PIPE_CONNECTION_STATE;

typedef struct _PIPE_CONNECTION
{
	LPWSTR		wszPipeName;
	OVERLAPPED	oOverlap;
	HANDLE		hPipeInst;
	/* Append one byte to make sure we always have room for \0 */
	BYTE		  pRequest[BUFSIZE + 1];
	DWORD		 dwRequest;
	BYTE		  pReply[BUFSIZE + 1];
	int			  reply_index;
	DWORD		 dwReply;
	DWORD		 dwState;
} PIPE_CONNECTION;

static PIPE_CONNECTION* g_pConnection = NULL;

static VOID
Usage(WCHAR* wszProgName)
{
	wprintf(L"A tool to monitor VM serial port output or send message to VM serial port.\n");
	wprintf(L"Usage: %s %s <Named pipe to monitor>\n", wszProgName, PIPE_READ_STR);
	wprintf(L"or\n");
	wprintf(L"	   %s %s <Named pipe to Monitor> <timeout in seconds> <message>\n",
			wszProgName, PIPE_SEND_STR);
}

static DWORD
ProcessCmdline(int argc, WCHAR* argv[],
			   OUT LPWSTR* pwszPipeName,
			   OUT LPWSTR* pwszCmdLine,
			   OUT DWORD* pdwTimeoutSeconds,
			   OUT PIPE_WORKMODE* peWorkMode)
{
	DWORD dwRet = ERROR_SUCCESS;
	long lTimeoutSeconds = 0;

	if (argc == 3)
	{
		if (!_wcsicmp(argv[1], PIPE_READ_STR))
		{
			(*peWorkMode) = PIPE_READMODE;
			(*pwszPipeName) = argv[2];
			(*pwszCmdLine) = NULL;
		}
		else
		{
			Usage(argv[0]);
			dwRet = ERROR_INVALID_PARAMETER;
		}
	}
	else if (argc == 5)
	{
		if (!_wcsicmp(argv[1], PIPE_SEND_STR))
		{
			(*peWorkMode) = PIPE_SENDMODE;
			(*pwszPipeName) = argv[2];
			(*pwszCmdLine) = argv[4];
			lTimeoutSeconds = _wtol(argv[3]);
			if (lTimeoutSeconds <= 0)
			{
				Usage(argv[0]);
				dwRet = ERROR_INVALID_PARAMETER;
			}
			else
			{
				(*pdwTimeoutSeconds) = (DWORD)lTimeoutSeconds;
			}
		}
		else
		{
			Usage(argv[0]);
			dwRet = ERROR_INVALID_PARAMETER;
		}
	}
	else
	{
		Usage(argv[0]);
		dwRet = ERROR_INVALID_PARAMETER;
	}
	return dwRet;
}

static VOID
ClosePipeConnection(IN PIPE_CONNECTION* pConnection)
{
	if (pConnection)
	{
		free(pConnection->wszPipeName);
		CloseHandle(pConnection->hPipeInst);
		CloseHandle(pConnection->oOverlap.hEvent);
		LocalFree(pConnection);
	}
	return;
}

static DWORD
OpenPipeConnection(IN LPWSTR wszPipeName,
				   OUT PIPE_CONNECTION** ppConnection,
	   IN DWORD dwTimeoutSeconds)
{
	PIPE_CONNECTION* pConnection = NULL;
	DWORD dwRet = ERROR_SUCCESS;
	BOOL bRet = FALSE;
	BOOL fReconnected = FALSE;
	DWORD dwMode = 0;

	pConnection = (PIPE_CONNECTION*)LocalAlloc(LPTR, sizeof(PIPE_CONNECTION));
	CHK_LASTERR(pConnection, dwRet, Exit, (L"Failed on LocalAlloc()"));

	pConnection->wszPipeName = _wcsdup(wszPipeName);
	CHK_COND(pConnection->wszPipeName, Exit, (L"wcsdup(wszPipeName)"));

	pConnection->oOverlap.hEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	CHK_LASTERR(pConnection->oOverlap.hEvent != INVALID_HANDLE_VALUE,
				dwRet, Exit, (L"CreateEvent(oOverlap.hEvent)"));

	fReconnected = FALSE;
	while(TRUE)
	{
		pConnection->hPipeInst = CreateFileW(wszPipeName,
											 GENERIC_READ | GENERIC_WRITE,
											 0,
											 NULL,
											 OPEN_EXISTING,
											 FILE_FLAG_OVERLAPPED |
												 FILE_FLAG_NO_BUFFERING |
												 FILE_FLAG_WRITE_THROUGH,
											 NULL);

		if (pConnection->hPipeInst != INVALID_HANDLE_VALUE)
			break;

		dwRet = GetLastError();
		/* Only retry once */
		if (dwRet != ERROR_PIPE_BUSY)
		{
			if (!fReconnected)
			{
				LOG((L"Reconnecting %s...", wszPipeName));
				Sleep(dwTimeoutSeconds*1000);
				fReconnected = TRUE;
				continue;
			}
			else
				CHK_LASTERR(FALSE, dwRet, Exit, (L"Reconnecting pipe timeout"));
		}

		LOG((L"Waiting for named pipe..."));
		bRet = WaitNamedPipeW(wszPipeName, dwTimeoutSeconds*1000);
		CHK_LASTERR(bRet, dwRet, Exit, (L"Wait for named pipe timeout"));
	}

	dwMode = PIPE_READMODE_MESSAGE;
	bRet = SetNamedPipeHandleState(pConnection->hPipeInst,
										 &dwMode, NULL, NULL);
	CHK_LASTERR(bRet, dwRet, Exit, (L"SetNamedPipeHandleState()"));

	pConnection->dwState = PIPE_CONNECTING;
	pConnection->dwRequest = 0;
	pConnection->dwReply = 0;

	(*ppConnection) = pConnection;
	return ERROR_SUCCESS;

Exit:
	ClosePipeConnection(pConnection);
	return dwRet;
}

static BOOL WINAPI
OnConsoleCtrlC(IN DWORD dwCtrlType)
{
	if (dwCtrlType == CTRL_C_EVENT)
	{
		LOG((L"CTRL-C received. Exit."));
		ClosePipeConnection(g_pConnection);
	}
	return FALSE;
}

static DWORD
HandleReadPipeLoop(IN LPWSTR wszPipeName)
{
	DWORD dwRet = ERROR_SUCCESS;
	BOOL fSuccess = FALSE;
	PIPE_CONNECTION* pConnection = NULL;

	/* In Reading mode, we support reconnecting when named pipe is
	 * closed. This is useful when monitoring virtual serial port for
	 * Hyper-V machine.
	 */
	while (TRUE)
	{
		dwRet = OpenPipeConnection(wszPipeName, &pConnection, 5);
		if (dwRet != ERROR_SUCCESS)
		{
			LOG((L"Reconnecting to %s...", wszPipeName));
			Sleep(PIPE_TIMEOUT);
			continue;
		}
		g_pConnection = pConnection;

		while (TRUE)
		{
			/* For reading mode: we have only transition between 
			 * read and wait states.
			 */
			ResetEvent(pConnection->oOverlap.hEvent);
			fSuccess = ReadFile(pConnection->hPipeInst,
								pConnection->pRequest,
								BUFSIZE * sizeof(BYTE),
								&pConnection->dwRequest,
								&pConnection->oOverlap);
			if (!fSuccess)
			{
				dwRet = GetLastError();
				if (dwRet == ERROR_IO_PENDING)
				{
					dwRet = WaitForSingleObject(pConnection->oOverlap.hEvent, INFINITE);
					if (dwRet == WAIT_OBJECT_0)
					{
						/* Wait entil we get the data back */
						fSuccess = GetOverlappedResult(
							pConnection->hPipeInst,
							&pConnection->oOverlap,
							&pConnection->dwRequest,
							TRUE);

						if (!fSuccess)
						{
							dwRet = GetLastError();
							if (dwRet == ERROR_PIPE_NOT_CONNECTED ||
								dwRet == ERROR_BROKEN_PIPE)
							{
								dwRet = ERROR_SUCCESS;
								LOG((L"Pipe is closed from server. Reconnecting..."));
								break;
							}
							else
							{
								CHK_LASTERR(FALSE, dwRet, Exit, (L"GetOverlappedResult()"));
							}
						}

					}
					else
					{
						CHK_LASTERR(FALSE, dwRet, Exit,
							(L"WaitForSingleObject: Unknown error"));
					}

				}
				else if (dwRet == ERROR_MORE_DATA)
				{
					/* continue to process more data */
				}
				else if (dwRet == ERROR_PIPE_NOT_CONNECTED ||
						 dwRet == ERROR_BROKEN_PIPE)
				{
					LOG((L"Pipe is closed from server. Reconnecting..."));
					break;
				}
				else
				{
					/* Something wrong happens */
					CHK_LASTERR(FALSE, dwRet, Exit, (L"ReadFile(return FALSE)"));
				}
			}
			/* Now we should have data read from server. */

			pConnection->pRequest[pConnection->dwRequest] = '\0';
			printf("%s", pConnection->pRequest);
			pConnection->dwRequest = 0;
		}
		/* Break to here when pipe is closed from another side. Try
		 * reconnecting.
		 */
		ClosePipeConnection(g_pConnection);
		g_pConnection = NULL;
	}

Exit:
	ClosePipeConnection(g_pConnection);
	g_pConnection = NULL;
	return dwRet;
}

static DWORD
ConvertStrToByteSequence(IN LPWSTR wszCmdLine,
						 OUT BYTE** ppUTF8Bytes, OUT DWORD* pdwUTF8Bytes)
{
	DWORD dwRet = ERROR_SUCCESS;
	int nUTF8Bytes = 0;
	BYTE* pUTF8Bytes = NULL;

	/*
	 * A general idea is to convert a Unicode to an UTF8 sequence,
	 * before sending it through serial port. This is because Linux VM
	 * generally does not recognize Unicode directly. They use UTF-8.
	 */
	
	nUTF8Bytes = WideCharToMultiByte(CP_UTF8, 0,
									 wszCmdLine, -1,
									 NULL, 0, NULL, NULL);
	/*
	 * Special case: I noticed I have to append '\n' to buffer before
	 * sending it to named pipe, or the buffer will be put in some internal
	 * cache (not sure from Hyper-V side or system side) and won't show 
	 * up in guest VM.
	 *
	 * So, I add one more byte to allocated buffer, so we can append
	 * '\r\n' at the end of converted byte string.
	 *
	 * NOTE: We don't add only '\n', because named pipe will
	 * automatically add '\r', so it causes troubles when we try to
	 * remove our sent bytes from response.
	 */
	pUTF8Bytes = (BYTE *) LocalAlloc(LPTR, sizeof(BYTE) * (nUTF8Bytes + 2));
	CHK_LASTERR(pUTF8Bytes, dwRet, Exit,
				(L"WideCharToMultiByte(getlength)"));

	nUTF8Bytes = WideCharToMultiByte(CP_UTF8, 0,
									 wszCmdLine, -1,
									 (LPSTR) pUTF8Bytes, nUTF8Bytes,
									 NULL, NULL);
	CHK_LASTERR(nUTF8Bytes > 0, dwRet, Exit,
				(L"WideCharToMultiByte(convert)"));

	assert(pUTF8Bytes[nUTF8Bytes - 1] == '\0');

	pUTF8Bytes[nUTF8Bytes - 1] = '\r';
	pUTF8Bytes[nUTF8Bytes] = '\n';
	pUTF8Bytes[nUTF8Bytes + 1] = '\0';

	(*ppUTF8Bytes) = pUTF8Bytes;
	pUTF8Bytes = NULL;
	/* Returned length does not include '\0'*/
	(*pdwUTF8Bytes) = (DWORD)(nUTF8Bytes + 1);
Exit:
	LocalFree(pUTF8Bytes);
	return dwRet;
}

static DWORD
SendCommandToPipe(IN LPWSTR wszPipeName,
				  IN LPWSTR wszCmdLine, IN DWORD dwTimeoutSeconds)
{
	DWORD dwRet = ERROR_SUCCESS;
	BOOL  fSuccess = FALSE;
	PIPE_CONNECTION* pConnection = NULL;
	BYTE* pUTF8Bytes = NULL;
	DWORD dwUTF8Bytes = 0;
	DWORD dwBytesWritten = 0;
	DWORD dwEachWaitMilliseconds = dwTimeoutSeconds * 1000;
	BYTE* pData = NULL;
	BYTE pOutput[BUFSIZE+1];
	DWORD dwOutput;
//	BOOL fContinueReading = FALSE;

	/* Convert wszCmdLine to byte sequence. Serial port does not
	 * recognize Unicode. */
	dwRet = ConvertStrToByteSequence(wszCmdLine,
										 &pUTF8Bytes, &dwUTF8Bytes);
	CHK_COND(dwRet == ERROR_SUCCESS, Exit, (L"ConvertStrToByteSequence()"));
	dwRet = ERROR_INVALID_PARAMETER;
	CHK_COND(dwUTF8Bytes > 0, Exit, (L"strlen(string+'\\0') == 0"));
	CHK_COND(dwUTF8Bytes < BUFSIZE, Exit, (L"Command line too long"));
	
	/* In Sending mode, we don't support reconnecting named pipe,
	 * because this feature is not really needed, but just to make
	 * user confused when a VM goes offline.
	 */
	dwRet = OpenPipeConnection(wszPipeName, &pConnection, dwTimeoutSeconds);
	CHK_COND(dwRet == ERROR_SUCCESS, Exit,
			 (L"OpenPipeConnection(%s)", wszPipeName));

	memcpy(pConnection->pRequest, pUTF8Bytes, dwUTF8Bytes);
	pData = pConnection->pRequest;
	pConnection->dwRequest = dwUTF8Bytes;
	g_pConnection = pConnection;

	/*
	 * For sendcmd mode: we have a transition between:
	 * io pending
	 * -> write request
	 *  -> read reply
	 *   -> print result
	 *	-> Exit
	 */
	pConnection->dwState = PIPE_WRITING;
	while (pConnection->dwState != PIPE_COMPLETE)
	{
		switch(pConnection->dwState)
		{
			case PIPE_WRITING:

				while(pConnection->dwRequest > 0)
				{
					ResetEvent(pConnection->oOverlap.hEvent);
					fSuccess = WriteFile(pConnection->hPipeInst,
										 pData,
										 pConnection->dwRequest,
										 &dwBytesWritten,
										 &pConnection->oOverlap);
					if (!fSuccess)
					{
						dwRet = GetLastError();
						if (dwRet == ERROR_IO_PENDING)
						{
							dwRet = WaitForSingleObject(
											pConnection->oOverlap.hEvent,
											dwEachWaitMilliseconds);
							if (dwRet == WAIT_OBJECT_0)
							{
								fSuccess = GetOverlappedResult(
												   pConnection->hPipeInst,
												   &pConnection->oOverlap,
												   &dwBytesWritten,
												   TRUE);
								CHK_LASTERR(fSuccess, dwRet, Exit,
											(L"PIPE_WRITING GetOverlappedResult()"));
							}
							else if (dwRet == WAIT_TIMEOUT)
							{
								CHK_LASTERR(FALSE, dwRet, Exit,
										 (L"PIPE_WRITING WaitForSingleObject: timeout"));
							}
							else
							{
								CHK_LASTERR(FALSE, dwRet, Exit,
										 (L"PIPE_WRITING WaitForSingleObject: Unknown error"));
							}
						}
						else
						{
							CHK_LASTERR(FALSE, dwRet, Exit, (L"PIPE_WRITING WriteFile()"));
						}
					}

					/* If we have reached here, we have written something to the pipe */
					pConnection->dwRequest -= dwBytesWritten;
					pData += dwBytesWritten;
				}

				FlushFileBuffers(pConnection->hPipeInst);
				pConnection->dwState = PIPE_READING;
				break;

			case PIPE_READING:

				dwOutput = 0;
				while (TRUE)
				{
					ResetEvent(pConnection->oOverlap.hEvent);
					fSuccess = ReadFile(pConnection->hPipeInst,
										pConnection->pReply,
										BUFSIZE * sizeof(BYTE),
										&pConnection->dwReply,
										&pConnection->oOverlap);
					if (!fSuccess)
					{
						dwRet = GetLastError();
						if (dwRet == ERROR_IO_PENDING)
						{
							dwRet = WaitForSingleObject(
											pConnection->oOverlap.hEvent,
											dwEachWaitMilliseconds);
							if (dwRet == WAIT_OBJECT_0)
							{
								/* Wait entil we get the data back */
								fSuccess = GetOverlappedResult(
												   pConnection->hPipeInst,
												   &pConnection->oOverlap,
												   &pConnection->dwReply,
												   TRUE);
								CHK_LASTERR(fSuccess, dwRet, Exit,
											(L"PIPE_READING GetOverlappedResult()"));
							}
							else if (dwRet == WAIT_TIMEOUT)
							{
								CancelIo(pConnection->hPipeInst);
								CHK_LASTERR(FALSE, dwRet, Exit,
										 (L"PIPE_READING WaitForSingleObject: timeout"));
							}
							else
							{
								CancelIo(pConnection->hPipeInst);
								CHK_LASTERR(FALSE, dwRet, Exit,
										 (L"PIPE_READING WaitForSingleObject: Unknown error"));
							}
						}
						else if (dwRet == ERROR_MORE_DATA)
						{
							/* 
							 * We have more data pending for reading. We put
							 * them to the next ReadFile() operation.
							 */
						}
						else if (dwRet == ERROR_PIPE_NOT_CONNECTED ||
								 dwRet == ERROR_BROKEN_PIPE)
						{
							CHK_LASTERR(FALSE, dwRet, Exit,
									 (L"PIPE_READING Pipe is closed from remote side."));
						}
						else
						{
							/* Something wrong happens */
							CHK_LASTERR(FALSE, dwRet, Exit, (L"PIPE_READING ReadFile(return FALSE)"));
						}
					}

					if (!fSuccess && dwRet == ERROR_MORE_DATA)
					{
						continue;
					}

					/* If we have reached here, we have read something from the pipe */
					CHK_COND(dwOutput + pConnection->dwReply < BUFSIZE, Exit, (L"PIPE_READING BUFSIZE overrun"));

					memcpy(pOutput+dwOutput, pConnection->pReply, pConnection->dwReply);
					dwOutput += pConnection->dwReply;

					/* The windows line return is ASCII 13(\r), 10(\n) We are looking for a \n as the end of return line*/
					if (dwOutput>0 && pOutput[dwOutput-1] == '\n')
					{
						pOutput[dwOutput] = 0;
						printf("%s", pOutput);
						break;
					}
				}

				pConnection->dwState = PIPE_COMPLETE;
				break;

			case PIPE_COMPLETE:
				break;

			default:
				dwRet = ERROR_INVALID_PARAMETER;
				CHK_COND(FALSE, Exit, (L"Internal error: unknown state: %d", pConnection->dwState));
				break;
		}
	}

	/* fallthrough return code */
	dwRet = ERROR_SUCCESS;

Exit:
	ClosePipeConnection(g_pConnection);
	g_pConnection = NULL;
	LocalFree(pUTF8Bytes);
	return dwRet;
}

int __cdecl
wmain(int argc, WCHAR* argv[])
{
	DWORD dwRet = ERROR_SUCCESS;
	BOOL bSuccess = FALSE;
	LPWSTR wszPipeName = NULL;
	LPWSTR wszCmdLine = NULL;
	PIPE_WORKMODE eWorkMode = PIPE_READMODE;
	DWORD dwTimeoutSeconds = 0;

	dwRet = ProcessCmdline(argc, argv,
						   &wszPipeName, &wszCmdLine, &dwTimeoutSeconds,
						   &eWorkMode);
	CHK_COND(dwRet == ERROR_SUCCESS, Exit, (L"ProcessCmdline()"));

	/* Make sure we can properly release resources at CTRL-C event */
	bSuccess = SetConsoleCtrlHandler(OnConsoleCtrlC, TRUE);
	CHK_LASTERR(bSuccess, dwRet, Exit, (L"SetConsoleCtrlHandler"));

	switch(eWorkMode)
	{
		case PIPE_READMODE:
			dwRet = HandleReadPipeLoop(wszPipeName);
			break;
		case PIPE_SENDMODE:
			dwRet = SendCommandToPipe(wszPipeName,
									  wszCmdLine, dwTimeoutSeconds);
			break;
		default: /* Should NEVER happen */
			dwRet = ERROR_INVALID_PARAMETER;
			break;
	}

Exit:
	ClosePipeConnection(g_pConnection);
	return dwRet;
}
