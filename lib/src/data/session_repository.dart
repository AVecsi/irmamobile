import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../models/attribute.dart';
import '../models/credentials.dart';
import '../models/return_url.dart';
import '../models/session.dart';
import '../models/session_events.dart';
import '../models/session_state.dart';
import '../models/translated_value.dart';
import '../util/con_dis_con.dart';
import 'irma_repository.dart';

// Typedefs are still experimental in Flutter. Therefore, we use inheritance for now.
class SessionStates extends UnmodifiableMapView<int, SessionState> {
  SessionStates(Map<int, SessionState> map) : super(map);
}

class SessionRepository {
  final IrmaRepository repo;

  final _sessionStatesSubject = BehaviorSubject<SessionStates>.seeded(SessionStates({}));

  SessionRepository({required this.repo, required Stream<SessionEvent> sessionEventStream}) {
    // Don't pipe states to the subject directly, because then potential errors are piped to the subject as well.
    sessionEventStream.listen((event) {
      final prevStates = _sessionStatesSubject.value;
      // Calculate the nextState from the previousState by handling the event.
      // In case a new session is created, we create a new session state.
      SessionState? nextState;
      if (prevStates.containsKey(event.sessionID)) {
        debugPrint('_eventHandler\n\n\n');
        debugPrintStack(label: 'SessionRepository stack', stackTrace: StackTrace.current, maxFrames: 50);

        debugPrint('SessionRepository stack2 \n\n\n ${StackTrace.current.toString()}');
        final prevState = prevStates[event.sessionID]!;
        nextState = _eventHandler(prevState, event);
      } else if (event is NewSessionEvent) {
        nextState = _newSessionState(event);
      }

      // Copy the prevStates into a new map, and add the next state
      final nextStates = Map.of(prevStates);
      if (nextState != null) nextStates[event.sessionID] = nextState;

      _sessionStatesSubject.add(SessionStates(nextStates));
    }, onDone: _sessionStatesSubject.close);
  }

  SessionState _newSessionState(NewSessionEvent event) {
    // Set the url as fallback serverName in case session is canceled before the translated serverName is known.
    RequestorInfo serverName;
    try {
      final url = Uri.parse(event.request.u).host;
      serverName = RequestorInfo(name: TranslatedValue.fromString(url));
    } catch (_) {
      // Error with url will be resolved by bridge, so we don't have to act on that.
      serverName = RequestorInfo(name: const TranslatedValue.empty());
    }
    return SessionState(
      sessionID: event.sessionID,
      clientReturnURL: ReturnURL.parse(event.request.returnURL),
      continueOnSecondDevice: event.request.continueOnSecondDevice,
      previouslyLaunchedCredentials: event.previouslyLaunchedCredentials,
      status: SessionStatus.initialized,
      serverName: serverName,
      sessionType: event.request.irmaqr,
    );
  }

  SessionState _eventHandler(SessionState prevState, SessionEvent event) {
    if (event is FailureSessionEvent) {
      return prevState.copyWith(
        status: SessionStatus.error,
        error: event.error,
      );
    } else if (event is KeyshareEnrollmentMissingSessionEvent) {
      return prevState.copyWith(
        status: SessionStatus.error,
        error: SessionError(
          errorType: 'keyshareEnrollmentMissing',
          info: 'user not activated at the keyshare server of scheme ${event.schemeManagerID}',
        ),
      );
    } else if (event is KeyshareEnrollmentIncompleteSessionEvent) {
      return prevState.copyWith(
        status: SessionStatus.error,
        error: SessionError(
          errorType: 'keyshareEnrollmentIncomplete',
          info: 'user enrollment incomplete at the keyshare server of scheme ${event.schemeManagerID}',
        ),
      );
    } else if (event is KeyshareEnrollmentDeletedSessionEvent) {
      return prevState.copyWith(
        status: SessionStatus.error,
        error: SessionError(
          errorType: 'keyshareEnrollmentDeleted',
          info: 'user deleted at the keyshare server of scheme ${event.schemeManagerID}',
        ),
      );
    } else if (event is StatusUpdateSessionEvent) {
      return prevState.copyWith(
        status: event.status.toSessionStatus(),
      );
    } else if (event is ClientReturnURLSetSessionEvent) {
      return prevState.copyWith(
        clientReturnURL: ReturnURL.parse(event.clientReturnURL),
      );
    } else if (event is PairingRequiredSessionEvent) {
      return prevState.copyWith(
        status: SessionStatus.pairing,
        pairingCode: event.pairingCode,
      );
    } else if (event is RequestIssuancePermissionSessionEvent) {
      try {
        _validateCandidates(event.disclosuresCandidates);
      } on SessionError catch (e) {
        return prevState.copyWith(status: SessionStatus.error, error: e);
      }
      // All discons must have an option to choose from. Otherwise the session can never be finished.
      final canBeFinished = event.disclosuresCandidates.every((discon) => discon.isNotEmpty);

      debugPrint('RequestIssuancePermissionSessionEvent\n\n\n ${event.disclosuresCandidates.isEmpty}\n\n\n');

      return prevState.copyWith(
        status: event.disclosuresCandidates.isEmpty
            ? SessionStatus.requestIssuancePermission
            : SessionStatus.requestDisclosurePermission,
        serverName: event.serverName,
        satisfiable: event.satisfiable,
        canBeFinished: canBeFinished,
        isSignatureSession: false,
        disclosuresCandidates: ConDisCon.fromRaw(event.disclosuresCandidates, (DisclosureCandidate dc) => dc),
        issuedCredentials: event.issuedCredentials
            .map((raw) => Credential.fromRaw(
                  irmaConfiguration: repo.irmaConfiguration,
                  rawCredential: raw,
                ))
            .toList(),
      );
    } else if (event is RequestVerificationPermissionSessionEvent) {
      try {
        debugPrint('Validating candidates\n\n\n');
        _validateCandidates(event.disclosuresCandidates);
      } on SessionError catch (e) {
        return prevState.copyWith(status: SessionStatus.error, error: e);
      }
      // All discons must have an option to choose from. Otherwise the session can never be finished.
      final canBeFinished = event.disclosuresCandidates.every((discon) => discon.isNotEmpty);

      debugPrint('Status\n\n\n ${canBeFinished}\n\n\n');

      debugPrint(
          'Instance of SessionState\n\n\n status: ${SessionStatus.requestDisclosurePermission}\n serverName: ${event.serverName}\n satisfiable: ${event.satisfiable}\n canBeFinished: ${canBeFinished}\n isSignatureSession: ${event.isSignatureSession}\n signedMessage: ${event.signedMessage}\n event.disclosuresCandidates: ${event.disclosuresCandidates}\n disclosuresCandidates: ${ConDisCon.fromRaw(event.disclosuresCandidates, (DisclosureCandidate dc) => dc)}\n\n\n');

      return prevState.copyWith(
        status: SessionStatus.requestDisclosurePermission,
        serverName: event.serverName,
        satisfiable: event.satisfiable,
        canBeFinished: canBeFinished,
        isSignatureSession: event.isSignatureSession,
        signedMessage: event.signedMessage,
        disclosuresCandidates: ConDisCon.fromRaw(event.disclosuresCandidates, (DisclosureCandidate dc) => dc),
      );
    } else if (event is ContinueToIssuanceEvent) {
      return prevState.copyWith(
        status: SessionStatus.requestIssuancePermission,
        disclosureChoices: ConCon.fromRaw(event.disclosureChoices, (AttributeIdentifier attrId) => attrId),
      );
    } else if (event is SuccessSessionEvent) {
      return prevState.copyWith(
        status: SessionStatus.success,
      );
    } else if (event is CanceledSessionEvent) {
      return prevState.copyWith(status: SessionStatus.canceled);
    } else if (event is RequestPinSessionEvent) {
      return prevState.copyWith(
        status: SessionStatus.requestPin,
      );
    } else if (event is RespondPermissionEvent) {
      return prevState.copyWith(
        status: SessionStatus.communicating,
        disclosureChoices:
            event.proceed ? ConCon.fromRaw(event.disclosureChoices, (AttributeIdentifier attrId) => attrId) : null,
        dismissed: !event.proceed,
      );
    }

    return prevState;
  }

  void _validateCandidates(List<List<List<DisclosureCandidate>>> candidates) {
    for (final discon in candidates) {
      for (final con in discon) {
        for (final cand in con) {
          // We support cand.type consisting of four dot-separated parts; three parts is forbidden here;
          // any other amount of parts is forbidden by irmago before we end up here
          if (cand.type.split('.').length == 3) {
            throw SessionError(
              errorType: 'notSupported',
              info: 'non-attribute disclosures are not supported',
              wrappedError: '"${cand.type}" consists of three parts; four expected',
            );
          }
        }
      }
    }
  }

  SessionState? getCurrentSessionState(int sessionID) => _sessionStatesSubject.value[sessionID];

  Stream<SessionState> getSessionState(int sessionID) => _sessionStatesSubject
      .where((sessionStates) => sessionStates.containsKey(sessionID))
      .map((sessionStates) => sessionStates[sessionID]!);

  Future<bool> hasActiveSessions() async {
    final sessions = await _sessionStatesSubject.first;
    return sessions.values.any((session) => session.status == SessionStatus.requestDisclosurePermission);
  }
}
