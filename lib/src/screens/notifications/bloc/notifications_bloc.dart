import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../../data/irma_repository.dart';
import '../../../sentry/sentry.dart';
import '../handlers/credential_status_notifications_handler.dart';
import '../handlers/notification_handler.dart';
import '../models/notification.dart';

part 'notifications_event.dart';
part 'notifications_state.dart';

class NotificationsBloc extends Bloc<NotificationsEvent, NotificationsState> {
  final IrmaRepository _repo;
  List<Notification> _notifications = [];

  final List<NotificationHandler> _notificationHandlers = [
    CredentialStatusNotificationsHandler(),
  ];

  NotificationsBloc({
    required IrmaRepository repo,
  })  : _repo = repo,
        super((NotificationsInitial())) {
    // The Initialize event should be called right after the bloc is created
    // It reads from cache, cleans up the notifications and loads new ones
    on<Initialize>(_mapInitToState, transformer: sequential());
    on<LoadNotifications>(_mapLoadNotificationsToState, transformer: sequential());
    on<MarkAllNotificationsAsRead>(_mapMarkAllNotificationsAsReadToState, transformer: sequential());
    on<MarkNotificationAsRead>(_mapMarkNotificationAsReadToState, transformer: sequential());
    on<SoftDeleteNotification>(_mapSoftDeleteNotificationToState, transformer: sequential());
  }

  Future<void> _mapInitToState(Initialize event, Emitter<NotificationsState> emit) async {
    emit(NotificationsLoading());

    List<Notification> initialNotifications = [];

    // Load the cached notifications
    final serializedNotifications = await _repo.preferences.getSerializedNotifications().first;
    initialNotifications = _notificationsFromJson(serializedNotifications);

    // Run the clean up method of each notification handler
    for (final notificationHandler in _notificationHandlers) {
      initialNotifications = notificationHandler.cleanUp(_repo, initialNotifications);
    }

    // Load the new notifications
    for (final notificationHandler in _notificationHandlers) {
      initialNotifications = await notificationHandler.loadNotifications(_repo, initialNotifications);
    }

    // Update the cached notifications
    _updateCachedNotifications(initialNotifications);

    _notifications = initialNotifications;

    final filteredNotifications = _filterNonSoftDeletedNotifications(_notifications);
    emit(NotificationsInitialized(filteredNotifications));
  }

  Future<void> _mapLoadNotificationsToState(LoadNotifications event, Emitter<NotificationsState> emit) async {
    emit(NotificationsLoading());

    List<Notification> updatedNotifications = _notifications;

    // Load the new notifications
    for (final notificationHandler in _notificationHandlers) {
      updatedNotifications = await notificationHandler.loadNotifications(_repo, updatedNotifications);
    }

    // Update the cached notifications
    _updateCachedNotifications(updatedNotifications);

    _notifications = updatedNotifications;
    final filteredNotifications = _filterNonSoftDeletedNotifications(_notifications);

    emit(NotificationsInitialized(filteredNotifications));
  }

  Future<void> _mapMarkAllNotificationsAsReadToState(
      MarkAllNotificationsAsRead event, Emitter<NotificationsState> emit) async {
    emit(NotificationsLoading());

    final List<Notification> updatedNotifications = _notifications;

    for (final notification in updatedNotifications) {
      notification.read = true;
    }

    _updateCachedNotifications(updatedNotifications);

    _notifications = updatedNotifications;
    final filteredNotifications = _filterNonSoftDeletedNotifications(_notifications);

    emit(NotificationsLoaded(filteredNotifications));
  }

  Future<void> _mapMarkNotificationAsReadToState(
      MarkNotificationAsRead event, Emitter<NotificationsState> emit) async {
    emit(NotificationsLoading());

    final List<Notification> updatedNotifications = _notifications;

    final notificationIndex =
        updatedNotifications.indexWhere((notification) => notification.id == event.notificationId);
    if (notificationIndex != -1) {
      updatedNotifications[notificationIndex].read = true;
    }
    _updateCachedNotifications(updatedNotifications);

    _notifications = updatedNotifications;
    final filteredNotifications = _filterNonSoftDeletedNotifications(_notifications);

    emit(NotificationsLoaded(filteredNotifications));
  }

  Future<void> _mapSoftDeleteNotificationToState(
      SoftDeleteNotification event, Emitter<NotificationsState> emit) async {
    emit(NotificationsLoading());

    final List<Notification> updatedNotifications = _notifications;

    final notificationIndex =
        updatedNotifications.indexWhere((notification) => notification.id == event.notificationId);
    if (notificationIndex != -1) {
      updatedNotifications[notificationIndex].softDeleted = true;
    }
    _updateCachedNotifications(updatedNotifications);

    _notifications = updatedNotifications;
    final filteredNotifications = _filterNonSoftDeletedNotifications(_notifications);

    emit(NotificationsLoaded(filteredNotifications));
  }

  List<Notification> _filterNonSoftDeletedNotifications(Iterable<Notification> notifications) {
    final filteredNotifications = notifications.where((notification) => !notification.softDeleted).toList();
    return filteredNotifications;
  }

  Future<void> _updateCachedNotifications(List<Notification> updatedNotifications) async {
    final serializedNotifications = _notificationsToJson(updatedNotifications);
    await _repo.preferences.setSerializedNotifications(serializedNotifications);
  }

  List<Notification> _notificationsFromJson(String serializedNotifications) {
    List<Notification> notifications = [];

    try {
      if (serializedNotifications != '') {
        final jsonDecodedNotifications = jsonDecode(serializedNotifications);
        notifications = jsonDecodedNotifications
            .map<Notification>(
              (jsonDecodedNotification) => Notification.fromJson(jsonDecodedNotification),
            )
            .toList();
      }
    } catch (e, stackTrace) {
      // If the cache is corrupted, we report the error to Sentry
      reportError(e, stackTrace);

      // If the cache is corrupted, we clear it and return an empty list
      _repo.preferences.setSerializedNotifications('');
    }

    return notifications;
  }

  String _notificationsToJson(List<Notification> notifications) {
    final mappedNotifications = notifications.map((notification) => notification.toJson()).toList();
    return jsonEncode(mappedNotifications);
  }
}
