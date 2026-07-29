import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/irma_repository.dart';
import '../../../models/change_pin_events.dart';
import '../../../models/session.dart';
import 'change_pin_event.dart';
import 'change_pin_state.dart';
import 'validation_state.dart';

class ChangePinBloc extends Bloc<PinEvent, ChangePinState> {
  final IrmaRepository repo;
  ChangePinBloc(this.repo) : super(const ChangePinState()) {
    on<PinEvent>(_onEvent, transformer: sequential());
  }

  Future<void> _onEvent(PinEvent event, Emitter<ChangePinState> emit) async {
    switch (event.type) {
      case PinEventType.oldPinEntered:
        emit(state.copyWith(
          oldPin: event.pin,
        ));
        break;
      case PinEventType.newPinChosen:
        emit(state.copyWith(
          newPin: event.pin,
        ));
        break;
      case PinEventType.newPinConfirmed:
        final changePinEvent = await repo.changePin(state.oldPin, state.newPin);
        if (changePinEvent is ChangePinSuccessEvent) {
          emit(state.copyWith(
            newPinConfirmed: ValidationState.valid,
          ));
        } else if (changePinEvent is ChangePinErrorEvent) {
          emit(state.copyWith(
            newPinConfirmed: ValidationState.error,
            error: changePinEvent.error,
          ));
        } else if (changePinEvent is ChangePinFailedEvent) {
          emit(state.copyWith(
            newPinConfirmed: ValidationState.error,
            error: SessionError(errorType: 'Unexpected Error', info: 'Unexpected old pin rejection by server'),
          ));
        }
        break;
    }
  }
}
