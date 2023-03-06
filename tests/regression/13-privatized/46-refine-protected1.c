#include <pthread.h>
#include <goblint.h>

int g = 0;

pthread_mutex_t A = PTHREAD_MUTEX_INITIALIZER;

void *t_fun(void *arg) {
  // just for going to multithreaded mode
  return NULL;
}

int main() {
  pthread_t id;
  int top;

  if(top) {
    pthread_mutex_lock(&A);
    g = 1;
    pthread_mutex_unlock(&A);
  }

  pthread_create(&id, NULL, t_fun, NULL);

  pthread_mutex_lock(&A);
  if (g) // protected globals should be refined
    __goblint_check(g);
  else
    __goblint_check(!g);
  pthread_mutex_unlock(&A);

  return 0;
}
